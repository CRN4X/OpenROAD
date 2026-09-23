// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#include "ir_solver_3d.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <queue>
#include <set>
#include <utility>
#include <vector>

#include "Eigen/Core"
#include "Eigen/SparseLU"
#include "connection.h"
#include "ir_network_3d.h"
#include "odb/db.h"
#include "utl/Logger.h"

namespace psm {

IRSolver3D::IRSolver3D(odb::dbChipNet* chip_net, utl::Logger* logger)
    : logger_(logger), network_(std::make_unique<IRNetwork3D>(chip_net, logger))
{
}

void IRSolver3D::build()
{
  network_->construct();
  buildConductanceMatrix();
  buildCurrentVector();
}

void IRSolver3D::addCurrentLoad(odb::dbChipInst* chip_inst,
                                odb::dbBTerm* bterm,
                                Current current)
{
  current_loads_.push_back({chip_inst, bterm, current});
}

void IRSolver3D::addVoltageSource(odb::dbChipInst* chip_inst,
                                  odb::dbBTerm* bterm,
                                  Voltage voltage)
{
  voltage_sources_.push_back({chip_inst, bterm, voltage});
}

Connection::ResistanceMap IRSolver3D::getResistanceMap() const
{
  Connection::ResistanceMap resistance;
  for (odb::dbTechLayer* layer : network_->getLayers()) {
    const Connection::Resistance layer_resistance = layer->getResistance();
    if ((layer->getType() == odb::dbTechLayerType::ROUTING
         || layer->getType() == odb::dbTechLayerType::CUT)
        && layer_resistance <= 0.0) {
      logger_->error(utl::PSM,
                     107,
                     "Layer {} has no positive resistance for the 3D G "
                     "matrix.",
                     layer->getName());
    }
    resistance[layer] = layer_resistance;
  }
  return resistance;
}

void IRSolver3D::buildConductanceMatrix()
{
  node_index_.clear();

  std::size_t index = 0;
  for (Node* node : network_->getNodes()) {
    node_index_[node] = index++;
  }

  g_matrix_.resize(node_index_.size(), node_index_.size());
  const Connection::ResistanceMap resistance_map = getResistanceMap();
  std::vector<Eigen::Triplet<Connection::Conductance>> matrix_values;
  matrix_values.reserve(network_->getConnectionCount() * 4);

  for (Connection* connection : network_->getConnections()) {
    const Connection::Resistance resistance
        = connection->getResistance(resistance_map);
    if (resistance <= 0.0) {
      logger_->error(utl::PSM,
                     108,
                     "A 3D power-grid connection has non-positive "
                     "resistance {}.",
                     resistance);
    }

    Node* node0 = connection->getNode0();
    Node* node1 = connection->getNode1();
    if (node0 == node1) {
      logger_->error(
          utl::PSM, 109, "A 3D power-grid connection forms a node loop.");
    }

    const std::size_t node0_index = node_index_.at(node0);
    const std::size_t node1_index = node_index_.at(node1);
    const Connection::Conductance conductance = 1.0 / resistance;

    matrix_values.emplace_back(node0_index, node0_index, conductance);
    matrix_values.emplace_back(node1_index, node1_index, conductance);
    matrix_values.emplace_back(node0_index, node1_index, -conductance);
    matrix_values.emplace_back(node1_index, node0_index, -conductance);
  }

  g_matrix_.setFromTriplets(matrix_values.begin(), matrix_values.end());
  g_matrix_.prune(0.0);
  g_matrix_.makeCompressed();
}

void IRSolver3D::buildCurrentVector()
{
  j_vector_ = CurrentVector::Zero(node_index_.size());
  for (const CurrentLoad& load : current_loads_) {
    Node* node = network_->findBTermNode(load.chip_inst, load.bterm);
    if (node == nullptr) {
      logger_->error(
          utl::PSM,
          114,
          "Cannot map current load at port {} on chiplet {} into "
          "the combined 3D network.",
          load.bterm == nullptr ? "<null>" : load.bterm->getName(),
          load.chip_inst == nullptr ? "<null>" : load.chip_inst->getName());
    }
    j_vector_[node_index_.at(node)] += load.current;
  }
}

std::size_t IRSolver3D::getNonZeroCurrentCount() const
{
  std::size_t count = 0;
  for (Eigen::Index index = 0; index < j_vector_.size(); index++) {
    if (j_vector_[index] != 0.0) {
      count++;
    }
  }
  return count;
}

bool IRSolver3D::checkCurrentVector() const
{
  constexpr double kTolerance = 1.0e-12;
  if (current_loads_.empty()
      || static_cast<std::size_t>(j_vector_.size()) != node_index_.size()) {
    return false;
  }

  CurrentVector expected = CurrentVector::Zero(node_index_.size());
  Current expected_total = 0.0;
  for (const CurrentLoad& load : current_loads_) {
    if (!std::isfinite(load.current) || load.current == 0.0) {
      return false;
    }
    Node* node = network_->findBTermNode(load.chip_inst, load.bterm);
    if (node == nullptr) {
      return false;
    }
    expected[node_index_.at(node)] += load.current;
    expected_total += load.current;
  }

  for (Eigen::Index index = 0; index < j_vector_.size(); index++) {
    if (!std::isfinite(j_vector_[index])
        || std::abs(j_vector_[index] - expected[index]) > kTolerance) {
      return false;
    }
  }
  return getNonZeroCurrentCount() > 0
         && std::abs(getTotalCurrent() - expected_total) <= kTolerance;
}

bool IRSolver3D::buildSourceMap(std::map<std::size_t, Voltage>& sources) const
{
  constexpr double kTolerance = 1.0e-12;
  sources.clear();
  for (const VoltageSource& source : voltage_sources_) {
    if (!std::isfinite(source.voltage)) {
      return false;
    }
    Node* node = network_->findBTermNode(source.chip_inst, source.bterm);
    if (node == nullptr) {
      return false;
    }
    const std::size_t index = node_index_.at(node);
    const auto [existing, inserted] = sources.emplace(index, source.voltage);
    if (!inserted && std::abs(existing->second - source.voltage) > kTolerance) {
      return false;
    }
  }
  return !sources.empty();
}

bool IRSolver3D::isConnected() const
{
  if (node_index_.empty()) {
    return false;
  }

  std::map<Node*, std::vector<Node*>> adjacency;
  for (Connection* connection : network_->getConnections()) {
    Node* node0 = connection->getNode0();
    Node* node1 = connection->getNode1();
    adjacency[node0].push_back(node1);
    adjacency[node1].push_back(node0);
  }

  std::set<Node*> visited;
  std::queue<Node*> pending;
  pending.push(node_index_.begin()->first);
  while (!pending.empty()) {
    Node* node = pending.front();
    pending.pop();
    if (!visited.insert(node).second) {
      continue;
    }
    for (Node* neighbor : adjacency[node]) {
      if (!visited.contains(neighbor)) {
        pending.push(neighbor);
      }
    }
  }
  return visited.size() == node_index_.size();
}

bool IRSolver3D::sourcesCoverAllComponents() const
{
  if (node_index_.empty()) {
    return false;
  }

  std::map<std::size_t, Voltage> sources;
  if (!buildSourceMap(sources)) {
    return false;
  }
  std::set<Node*> source_nodes;
  for (const auto& [node, index] : node_index_) {
    if (sources.contains(index)) {
      source_nodes.insert(node);
    }
  }

  std::map<Node*, std::vector<Node*>> adjacency;
  for (Connection* connection : network_->getConnections()) {
    Node* node0 = connection->getNode0();
    Node* node1 = connection->getNode1();
    adjacency[node0].push_back(node1);
    adjacency[node1].push_back(node0);
  }

  std::set<Node*> visited;
  for (const auto& entry : node_index_) {
    Node* start = entry.first;
    if (visited.contains(start)) {
      continue;
    }
    bool component_has_source = false;
    std::queue<Node*> pending;
    pending.push(start);
    while (!pending.empty()) {
      Node* node = pending.front();
      pending.pop();
      if (!visited.insert(node).second) {
        continue;
      }
      component_has_source |= source_nodes.contains(node);
      for (Node* neighbor : adjacency[node]) {
        if (!visited.contains(neighbor)) {
          pending.push(neighbor);
        }
      }
    }
    if (!component_has_source) {
      return false;
    }
  }
  return true;
}

bool IRSolver3D::solve()
{
  voltage_vector_.resize(0);
  if (!check() || !checkCurrentVector()) {
    return false;
  }

  std::map<std::size_t, Voltage> sources;
  if (!buildSourceMap(sources)) {
    return false;
  }

  CurrentVector right_hand_side = j_vector_;
  for (const auto& [source_index, source_voltage] : sources) {
    for (ConductanceMatrix::InnerIterator value(g_matrix_, source_index); value;
         ++value) {
      const std::size_t row = value.row();
      if (!sources.contains(row)) {
        right_hand_side[row] -= value.value() * source_voltage;
      }
    }
    right_hand_side[source_index] = source_voltage;
  }

  std::vector<Eigen::Triplet<Connection::Conductance>> matrix_values;
  matrix_values.reserve(g_matrix_.nonZeros() + sources.size());
  for (Eigen::Index column = 0; column < g_matrix_.outerSize(); column++) {
    for (ConductanceMatrix::InnerIterator value(g_matrix_, column); value;
         ++value) {
      if (!sources.contains(value.row()) && !sources.contains(value.col())) {
        matrix_values.emplace_back(value.row(), value.col(), value.value());
      }
    }
  }
  for (const auto& source : sources) {
    matrix_values.emplace_back(source.first, source.first, 1.0);
  }

  ConductanceMatrix constrained_matrix(g_matrix_.rows(), g_matrix_.cols());
  constrained_matrix.setFromTriplets(matrix_values.begin(),
                                     matrix_values.end());
  constrained_matrix.makeCompressed();

  Eigen::SparseLU<ConductanceMatrix> eigen_solver;
  eigen_solver.compute(constrained_matrix);
  if (eigen_solver.info() != Eigen::ComputationInfo::Success) {
    return false;
  }
  voltage_vector_ = eigen_solver.solve(right_hand_side);
  return eigen_solver.info() == Eigen::ComputationInfo::Success
         && checkSolution();
}

bool IRSolver3D::checkSolution() const
{
  constexpr double kTolerance = 1.0e-8;
  if (!hasSolution()) {
    return false;
  }

  std::map<std::size_t, Voltage> sources;
  if (!buildSourceMap(sources)) {
    return false;
  }
  for (Eigen::Index index = 0; index < voltage_vector_.size(); index++) {
    if (!std::isfinite(voltage_vector_[index])) {
      return false;
    }
  }
  for (const auto& [source_index, source_voltage] : sources) {
    if (std::abs(voltage_vector_[source_index] - source_voltage) > kTolerance) {
      return false;
    }
  }

  const CurrentVector calculated_current = g_matrix_ * voltage_vector_;
  for (Eigen::Index index = 0; index < calculated_current.size(); index++) {
    if (sources.contains(index)) {
      continue;
    }
    const double scale = std::max(
        {1.0, std::abs(calculated_current[index]), std::abs(j_vector_[index])});
    if (std::abs(calculated_current[index] - j_vector_[index])
        > kTolerance * scale) {
      return false;
    }
  }
  return true;
}

std::optional<IRSolver3D::Voltage> IRSolver3D::getVoltage(
    odb::dbChipInst* chip_inst,
    odb::dbBTerm* bterm) const
{
  if (!hasSolution()) {
    return std::nullopt;
  }
  Node* node = network_->findBTermNode(chip_inst, bterm);
  if (node == nullptr) {
    return std::nullopt;
  }
  const auto index = node_index_.find(node);
  if (index == node_index_.end()) {
    return std::nullopt;
  }
  return voltage_vector_[index->second];
}

bool IRSolver3D::check() const
{
  constexpr double kTolerance = 1.0e-9;
  if (static_cast<std::size_t>(g_matrix_.rows()) != node_index_.size()
      || static_cast<std::size_t>(g_matrix_.cols()) != node_index_.size()) {
    return false;
  }

  std::vector<double> row_sums(g_matrix_.rows(), 0.0);
  for (Eigen::Index column = 0; column < g_matrix_.outerSize(); column++) {
    for (ConductanceMatrix::InnerIterator value(g_matrix_, column); value;
         ++value) {
      if (!std::isfinite(value.value())) {
        return false;
      }
      if (std::abs(value.value() - g_matrix_.coeff(value.col(), value.row()))
          > kTolerance * std::max(1.0, std::abs(value.value()))) {
        return false;
      }
      row_sums[value.row()] += value.value();
    }
  }

  for (std::size_t row = 0; row < row_sums.size(); row++) {
    const double diagonal = std::abs(g_matrix_.coeff(row, row));
    if (diagonal == 0.0
        || std::abs(row_sums[row]) > kTolerance * std::max(1.0, diagonal)) {
      return false;
    }
  }

  std::map<std::pair<std::size_t, std::size_t>, Connection::Conductance>
      interdie_conductance;
  const Connection::ResistanceMap empty_resistance_map;
  for (const auto& connection : network_->getInterDieConnections()) {
    std::size_t node0 = node_index_.at(connection->getNode0());
    std::size_t node1 = node_index_.at(connection->getNode1());
    if (node1 < node0) {
      std::swap(node0, node1);
    }
    const Connection::Resistance resistance
        = connection->getResistance(empty_resistance_map);
    interdie_conductance[{node0, node1}] += 1.0 / resistance;
  }

  for (const auto& [nodes, conductance] : interdie_conductance) {
    const double matrix_value = g_matrix_.coeff(nodes.first, nodes.second);
    if (std::abs(matrix_value + conductance)
        > kTolerance * std::max(1.0, conductance)) {
      return false;
    }
  }

  return !node_index_.empty() && !interdie_conductance.empty() && isConnected();
}

}  // namespace psm
