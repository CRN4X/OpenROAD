// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2020-2025, The OpenROAD Authors

#include "psm/pdnsim.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#include "db_sta/dbSta.hh"
#include "debug_gui.h"
#include "dpl/Opendp.h"
#include "heatMap.h"
#include "ir_network.h"
#include "ir_network_3d.h"
#include "ir_solver.h"
#include "ir_solver_3d.h"
#include "node.h"
#include "odb/db.h"
#include "odb/dbShape.h"
#include "odb/dbTypes.h"
#include "shape.h"
#include "sta/Liberty.hh"
#include "utl/Logger.h"
#include "web/core.h"
#include "web/heatMap.h"

using odb::dbBlock;
using odb::dbSigType;

namespace psm {

PDNSim::PDNSim(utl::Logger* logger,
               odb::dbDatabase* db,
               sta::dbSta* sta,
               est::EstimateParasitics* estimate_parasitics,
               dpl::Opendp* opendp)
{
  db_ = db;
  sta_ = sta;
  estimate_parasitics_ = estimate_parasitics;
  opendp_ = opendp;
  logger_ = logger;
  heatmap_source_ = web::registerHeatMapSource(
      "IR Drop", "IRDrop", "IRDrop", [this, sta, logger]() {
        return std::make_shared<IRDropDataSource>(this, sta, logger);
      });
}

PDNSim::~PDNSim() = default;

void PDNSim::setDebugGui(bool enable)
{
  debug_gui_enabled_ = enable;

  for (const auto& [net, solver] : solvers_) {
    solver->enableGui(debug_gui_enabled_);
  }

  web::Gui::get()->registerDescriptor<Node*>(new NodeDescriptor(solvers_));
  web::Gui::get()->registerDescriptor<ITermNode*>(
      new ITermNodeDescriptor(solvers_));
  web::Gui::get()->registerDescriptor<BPinNode*>(
      new BPinNodeDescriptor(solvers_));
  web::Gui::get()->registerDescriptor<Connection*>(
      new ConnectionDescriptor(solvers_));
}

void PDNSim::setNetVoltage(odb::dbNet* net, sta::Scene* corner, double voltage)
{
  auto& voltages = user_voltages_[net];
  voltages[corner] = voltage;
}

void PDNSim::setInstPower(odb::dbInst* inst, sta::Scene* corner, float power)
{
  auto& powers = user_powers_[inst];
  powers[corner] = power;
}

void PDNSim::analyzePowerGrid(odb::dbNet* net,
                              sta::Scene* corner,
                              GeneratedSourceType source_type,
                              const std::string& voltage_file,
                              bool use_prev_solution,
                              bool enable_em,
                              const std::string& em_file,
                              const std::string& error_file,
                              const std::string& voltage_source_file)
{
  if (!checkConnectivity(net, false, error_file, false)) {
    return;
  }

  last_net_ = net;
  last_corner_ = corner;
  auto* solver = getIRSolver(net, false);
  if (!use_prev_solution || !solver->hasSolution(corner)) {
    solver->solve(corner, source_type, voltage_source_file);
  } else {
    logger_->info(utl::PSM, 11, "Reusing previous solution");
  }
  solver->report(corner);

  if (heatmap_source_) {
    heatmap_source_->invalidateInstances();
  }

  if (enable_em) {
    solver->reportEM(corner);
    solver->writeEMFile(em_file, corner);
  }

  solver->writeInstanceVoltageFile(voltage_file, corner);
}

bool PDNSim::checkConnectivity(odb::dbNet* net,
                               bool floorplanning,
                               const std::string& error_file,
                               bool require_bterm)
{
  auto* solver = getIRSolver(net, floorplanning);
  const bool check = solver->check(require_bterm, !floorplanning);
  solver->writeErrorFile(error_file);

  if (debug_gui_enabled_) {
    solver->enableGui(true);
  }

  if (logger_->debugCheck(utl::PSM, "stats", 1)) {
    solver->getNetwork()->reportStats();
  }

  if (check) {
    logger_->info(
        utl::PSM, 40, "All shapes on net {} are connected.", net->getName());
  } else {
    logger_->error(
        utl::PSM, 69, "Check connectivity failed on {}.", net->getName());
  }
  return check;
}

odb::dbChipNet* PDNSim::findChipNet(const std::string& chip_net_name) const
{
  odb::dbChip* top_chip = db_->getChip();
  if (top_chip == nullptr) {
    logger_->error(utl::PSM, 101, "No top-level dbChip is loaded.");
  }

  odb::dbChipNet* chip_net = nullptr;
  for (odb::dbChipNet* candidate : top_chip->getChipNets()) {
    if (candidate->getName() == chip_net_name) {
      chip_net = candidate;
      break;
    }
  }
  if (chip_net == nullptr) {
    logger_->error(utl::PSM, 102, "Cannot find dbChipNet {}.", chip_net_name);
  }
  return chip_net;
}

bool PDNSim::check3DPowerGrid(const std::string& chip_net_name)
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);

  auto network = std::make_unique<IRNetwork3D>(chip_net, logger_);
  network->construct();
  const bool stitched = network->getChipletNetworkCount() >= 2
                        && network->getInterDieConnectionCount() > 0;
  if (!stitched) {
    logger_->error(utl::PSM,
                   103,
                   "3D power grid {} has {} chiplet PDNs and {} inter-die "
                   "connections.",
                   chip_net_name,
                   network->getChipletNetworkCount(),
                   network->getInterDieConnectionCount());
  }

  logger_->info(utl::PSM,
                104,
                "Built 3D power grid {}: {} chiplet PDNs, {} nodes, and {} "
                "connections ({} inter-die).",
                chip_net_name,
                network->getChipletNetworkCount(),
                network->getNodeCount(),
                network->getConnectionCount(),
                network->getInterDieConnectionCount());
  networks_3d_[chip_net] = std::move(network);
  return true;
}

bool PDNSim::check3DGMatrix(const std::string& chip_net_name, bool require_tsv)
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);
  auto solver = std::make_unique<IRSolver3D>(chip_net, logger_);
  solver->build();
  if (!solver->isConnected()) {
    logger_->error(utl::PSM,
                   137,
                   "The combined 3D power grid for {} is disconnected.",
                   chip_net_name);
  }
  if (!solver->check()) {
    logger_->error(utl::PSM,
                   110,
                   "The combined 3D G matrix for {} is invalid.",
                   chip_net_name);
  }
  const std::size_t bridge_count
      = solver->getNetwork()->getBacksideBridgeConnectionCount();
  if (require_tsv && bridge_count == 0) {
    logger_->error(utl::PSM,
                   113,
                   "The combined 3D G matrix for {} has no backside TSV "
                   "bridge connection.",
                   chip_net_name);
  }

  logger_->info(utl::PSM,
                111,
                "Built combined 3D G matrix {}: {} nodes, {} nonzero "
                "entries, {} inter-die conductance stamps, and {} backside "
                "TSV bridge stamps.",
                chip_net_name,
                solver->getNodeCount(),
                solver->getNonZeroCount(),
                solver->getNetwork()->getInterDieConnectionCount(),
                bridge_count);
  solvers_3d_[chip_net] = std::move(solver);
  return true;
}

void PDNSim::add3DPDNCurrent(const std::string& chip_net_name,
                             const std::string& chip_name,
                             const std::string& port_name,
                             double current)
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);
  if (!std::isfinite(current) || current == 0.0) {
    logger_->error(utl::PSM,
                   115,
                   "Current injection at chiplet port {}/{} must be finite "
                   "and nonzero.",
                   chip_name,
                   port_name);
  }

  odb::dbChip* top_chip = db_->getChip();
  odb::dbChipInst* chip_inst = top_chip->findChipInst(chip_name.c_str());
  if (chip_inst == nullptr) {
    logger_->error(utl::PSM, 116, "Cannot find chiplet {}.", chip_name);
  }

  odb::dbBlock* block = chip_inst->getMasterChip()->getBlock();
  odb::dbBTerm* bterm = block->findBTerm(port_name.c_str());
  if (bterm == nullptr) {
    logger_->error(utl::PSM,
                   117,
                   "Cannot find port {} on chiplet {}.",
                   port_name,
                   chip_name);
  }

  bool belongs_to_chip_net = false;
  for (uint32_t index = 0; index < chip_net->getNumBumpInsts(); index++) {
    std::vector<odb::dbChipInst*> path;
    odb::dbChipBumpInst* bump_inst = chip_net->getBumpInst(index, path);
    if (bump_inst != nullptr && !path.empty() && path.back() == chip_inst
        && bump_inst->getChipBump()->getNet() == bterm->getNet()) {
      belongs_to_chip_net = true;
      break;
    }
  }
  if (!belongs_to_chip_net) {
    logger_->error(utl::PSM,
                   118,
                   "Port {} on chiplet {} is not connected to 3D net {}.",
                   port_name,
                   chip_name,
                   chip_net_name);
  }

  user_currents_3d_[chip_net].push_back({chip_inst, bterm, current});
  solvers_3d_.erase(chip_net);
}

bool PDNSim::check3DJVector(const std::string& chip_net_name)
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);
  auto solver = std::make_unique<IRSolver3D>(chip_net, logger_);
  const auto loads = user_currents_3d_.find(chip_net);
  if (loads != user_currents_3d_.end()) {
    for (const CurrentLoad3D& load : loads->second) {
      solver->addCurrentLoad(load.chip_inst, load.bterm, load.current);
    }
  }

  solver->build();
  if (!solver->check()) {
    logger_->error(utl::PSM,
                   123,
                   "The combined 3D G matrix for {} is invalid.",
                   chip_net_name);
  }
  if (!solver->checkCurrentVector()) {
    logger_->error(utl::PSM,
                   119,
                   "The combined 3D J vector for {} is invalid or has no "
                   "current loads.",
                   chip_net_name);
  }

  logger_->info(utl::PSM,
                120,
                "Built combined 3D J vector {}: {} entries, {} nonzero "
                "entries from {} loads, and {:.6g} A total current.",
                chip_net_name,
                solver->getNodeCount(),
                solver->getNonZeroCurrentCount(),
                solver->getCurrentLoadCount(),
                solver->getTotalCurrent());
  solvers_3d_[chip_net] = std::move(solver);
  return true;
}

void PDNSim::set3DPDNVoltageSource(const std::string& chip_net_name,
                                   const std::string& chip_name,
                                   const std::string& port_name,
                                   double voltage)
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);
  if (!std::isfinite(voltage)) {
    logger_->error(utl::PSM,
                   124,
                   "Voltage source at chiplet port {}/{} must be finite.",
                   chip_name,
                   port_name);
  }

  odb::dbChip* top_chip = db_->getChip();
  odb::dbChipInst* chip_inst = top_chip->findChipInst(chip_name.c_str());
  if (chip_inst == nullptr) {
    logger_->error(utl::PSM, 125, "Cannot find source chiplet {}.", chip_name);
  }

  odb::dbBlock* block = chip_inst->getMasterChip()->getBlock();
  odb::dbBTerm* bterm = block->findBTerm(port_name.c_str());
  if (bterm == nullptr) {
    logger_->error(utl::PSM,
                   126,
                   "Cannot find source port {} on chiplet {}.",
                   port_name,
                   chip_name);
  }

  bool belongs_to_chip_net = false;
  for (uint32_t index = 0; index < chip_net->getNumBumpInsts(); index++) {
    std::vector<odb::dbChipInst*> path;
    odb::dbChipBumpInst* bump_inst = chip_net->getBumpInst(index, path);
    if (bump_inst != nullptr && !path.empty() && path.back() == chip_inst
        && bump_inst->getChipBump()->getNet() == bterm->getNet()) {
      belongs_to_chip_net = true;
      break;
    }
  }
  if (!belongs_to_chip_net) {
    logger_->error(utl::PSM,
                   127,
                   "Source port {} on chiplet {} is not connected to 3D net "
                   "{}.",
                   port_name,
                   chip_name,
                   chip_net_name);
  }

  auto& sources = user_voltage_sources_3d_[chip_net];
  const auto existing = std::ranges::find_if(
      sources, [chip_inst, bterm](const VoltageSource3D& source) {
        return source.chip_inst == chip_inst && source.bterm == bterm;
      });
  if (existing == sources.end()) {
    sources.push_back({chip_inst, bterm, voltage});
  } else {
    existing->voltage = voltage;
  }
  solvers_3d_.erase(chip_net);
}

bool PDNSim::solve3DPowerGrid(const std::string& chip_net_name)
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);
  auto solver = std::make_unique<IRSolver3D>(chip_net, logger_);

  const auto loads = user_currents_3d_.find(chip_net);
  if (loads != user_currents_3d_.end()) {
    for (const CurrentLoad3D& load : loads->second) {
      solver->addCurrentLoad(load.chip_inst, load.bterm, load.current);
    }
  }
  const auto sources = user_voltage_sources_3d_.find(chip_net);
  if (sources != user_voltage_sources_3d_.end()) {
    for (const VoltageSource3D& source : sources->second) {
      solver->addVoltageSource(source.chip_inst, source.bterm, source.voltage);
    }
  }

  solver->build();
  if (solver->getVoltageSourceCount() == 0) {
    logger_->error(utl::PSM,
                   138,
                   "No package voltage source is defined for 3D net {}.",
                   chip_net_name);
  }
  if (!solver->sourcesCoverAllComponents()) {
    logger_->error(utl::PSM,
                   139,
                   "The constrained 3D G matrix for {} is singular because "
                   "at least one connected component has no voltage source.",
                   chip_net_name);
  }
  if (!solver->solve()) {
    logger_->error(utl::PSM,
                   128,
                   "Failed to solve the combined 3D power grid for {}. "
                   "Check its G matrix, J vector, and package voltage "
                   "sources.",
                   chip_net_name);
  }

  const auto& voltages = solver->getVoltageVector();
  logger_->info(utl::PSM,
                129,
                "Solved combined 3D power grid {}: {} nodes, {} current "
                "loads, {} fixed-voltage sources, and voltage range {:.6g} "
                "to {:.6g} V.",
                chip_net_name,
                solver->getNodeCount(),
                solver->getCurrentLoadCount(),
                solver->getVoltageSourceCount(),
                voltages.minCoeff(),
                voltages.maxCoeff());
  solvers_3d_[chip_net] = std::move(solver);
  return true;
}

double PDNSim::get3DPDNVoltage(const std::string& chip_net_name,
                               const std::string& chip_name,
                               const std::string& port_name) const
{
  odb::dbChipNet* chip_net = findChipNet(chip_net_name);
  const auto solver = solvers_3d_.find(chip_net);
  if (solver == solvers_3d_.end() || !solver->second->hasSolution()) {
    logger_->error(utl::PSM,
                   130,
                   "No 3D voltage solution is available for {}.",
                   chip_net_name);
  }

  odb::dbChipInst* chip_inst = db_->getChip()->findChipInst(chip_name.c_str());
  if (chip_inst == nullptr) {
    logger_->error(utl::PSM, 131, "Cannot find chiplet {}.", chip_name);
  }
  odb::dbBTerm* bterm
      = chip_inst->getMasterChip()->getBlock()->findBTerm(port_name.c_str());
  if (bterm == nullptr) {
    logger_->error(utl::PSM,
                   132,
                   "Cannot find port {} on chiplet {}.",
                   port_name,
                   chip_name);
  }

  const std::optional<double> voltage
      = solver->second->getVoltage(chip_inst, bterm);
  if (!voltage.has_value()) {
    logger_->error(utl::PSM,
                   133,
                   "Cannot map port {} on chiplet {} into the solved 3D net "
                   "{}.",
                   port_name,
                   chip_name,
                   chip_net_name);
  }
  return *voltage;
}

void PDNSim::writeSpiceNetwork(odb::dbNet* net,
                               sta::Scene* corner,
                               GeneratedSourceType source_type,
                               const std::string& spice_file,
                               const std::string& voltage_source_file)
{
  auto* solver = getIRSolver(net, false);
  solver->writeSpiceFile(source_type, spice_file, corner, voltage_source_file);
}

psm::IRSolver* PDNSim::getIRSolver(odb::dbNet* net, bool floorplanning)
{
  auto& solver = solvers_[net];
  if (solver == nullptr) {
    solver = std::make_unique<IRSolver>(net,
                                        floorplanning,
                                        sta_,
                                        estimate_parasitics_,
                                        logger_,
                                        user_voltages_,
                                        user_powers_,
                                        generated_source_settings_);
    addOwner(net->getBlock());
  }

  return solver.get();
}

void PDNSim::getIRDropForLayer(odb::dbNet* net,
                               odb::dbTechLayer* layer,
                               IRDropByPoint& ir_drop) const
{
  auto find_solver = solvers_.find(net);
  if (last_corner_ == nullptr || find_solver == solvers_.end()) {
    return;
  }
  ir_drop = find_solver->second->getIRDrop(layer, last_corner_);
}

void PDNSim::getIRDropForLayer(odb::dbNet* net,
                               sta::Scene* corner,
                               odb::dbTechLayer* layer,
                               IRDropByPoint& ir_drop) const
{
  auto find_solver = solvers_.find(net);
  if (find_solver == solvers_.end()) {
    return;
  }
  ir_drop = find_solver->second->getIRDrop(layer, corner);
}

void PDNSim::setGeneratedSourceSettings(const GeneratedSourceSettings& settings)
{
  if (settings.bump_dx > 0) {
    generated_source_settings_.bump_dx = settings.bump_dx;
  }
  if (settings.bump_dy > 0) {
    generated_source_settings_.bump_dy = settings.bump_dy;
  }
  if (settings.bump_interval > 0) {
    generated_source_settings_.bump_interval = settings.bump_interval;
  }
  if (settings.bump_size > 0) {
    generated_source_settings_.bump_size = settings.bump_size;
  }
  if (settings.strap_track_pitch > 0) {
    generated_source_settings_.strap_track_pitch = settings.strap_track_pitch;
  }
  if (settings.resistance > 0) {
    generated_source_settings_.resistance = settings.resistance;
  }
}

void PDNSim::clearSolvers()
{
  solvers_.clear();
  networks_3d_.clear();
  solvers_3d_.clear();
}

void PDNSim::inDbPostMoveInst(odb::dbInst*)
{
  clearSolvers();
}

void PDNSim::inDbNetDestroy(odb::dbNet*)
{
  clearSolvers();
}

void PDNSim::inDbBTermPostConnect(odb::dbBTerm*)
{
  clearSolvers();
}

void PDNSim::inDbBTermPostDisConnect(odb::dbBTerm*, odb::dbNet*)
{
  clearSolvers();
}

void PDNSim::inDbBPinCreate(odb::dbBPin*)
{
  clearSolvers();
}

void PDNSim::inDbBPinAddBox(odb::dbBox*)
{
  clearSolvers();
}

void PDNSim::inDbBPinRemoveBox(odb::dbBox*)
{
  clearSolvers();
}

void PDNSim::inDbBPinDestroy(odb::dbBPin*)
{
  clearSolvers();
}

void PDNSim::inDbSWireAddSBox(odb::dbSBox*)
{
  clearSolvers();
}

void PDNSim::inDbSWireRemoveSBox(odb::dbSBox*)
{
  clearSolvers();
}

void PDNSim::inDbSWirePostDestroySBoxes(odb::dbSWire*)
{
  clearSolvers();
}

void PDNSim::inDbFillCreate(odb::dbFill*)
{
  clearSolvers();
}

// Functions of decap cells
void PDNSim::addDecapMaster(odb::dbMaster* decap_master, double decap_cap)
{
  opendp_->addDecapMaster(decap_master, decap_cap);
}

// Return the lowest layer of db_net route
odb::dbTechLayer* PDNSim::getLowestLayer(odb::dbNet* db_net)
{
  int min_layer_level = std::numeric_limits<int>::max();
  std::vector<odb::dbShape> via_boxes;
  for (odb::dbSWire* swire : db_net->getSWires()) {
    for (odb::dbSBox* s : swire->getWires()) {
      if (!s->isVia()) {
        odb::dbTechLayer* tech_layer = s->getTechLayer();
        min_layer_level
            = std::min(min_layer_level, tech_layer->getRoutingLevel());
      }
    }
  }
  return db_->getTech()->findRoutingLayer(min_layer_level);
}

odb::dbNet* PDNSim::findPowerNet(const char* net_name)
{
  dbBlock* block = db_->getChip()->getBlock();
  odb::dbNet* power_net = nullptr;
  // If net name is defined by user
  if (!std::string(net_name).empty()) {
    power_net = block->findNet(net_name);
    if (power_net == nullptr) {
      logger_->error(
          utl::PSM, 48, "Cannot find net {} in the design.", net_name);
    }
    // Check if net is supply
    if (!power_net->getSigType().isSupply()) {
      logger_->error(
          utl::PSM, 47, "{} is not a supply net.", power_net->getName());
    }
    return power_net;
  }
  // Otherwise find power net
  for (auto db_net : block->getNets()) {
    if (db_net->getSigType().isSupply()
        && db_net->getSigType() == dbSigType::POWER) {
      power_net = db_net;
      break;
    }
  }
  return power_net;
}

void PDNSim::insertDecapCells(double target, const char* net_name)
{
  // Get db_net
  odb::dbNet* db_net = findPowerNet(net_name);

  // Get lowest layer
  odb::dbTechLayer* tech_layer = getLowestLayer(db_net);

  IRDropByPoint ir_drops;
  getIRDropForLayer(db_net, tech_layer, ir_drops);

  if (ir_drops.empty()) {
    logger_->error(utl::PSM,
                   93,
                   "No IR drop data found. Run analyse_power_grid for net {} "
                   "before inserting decap cells.",
                   db_net->getName());
  }

  // call DPL to insert decap cells
  opendp_->insertDecapCells(target, ir_drops);
}

}  // namespace psm
