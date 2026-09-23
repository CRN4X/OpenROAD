// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#include "ir_network_3d.h"

#include <algorithm>
#include <memory>
#include <vector>

#include "ir_network.h"
#include "node.h"
#include "odb/db.h"
#include "utl/Logger.h"

namespace psm {

IRNetwork3D::IRNetwork3D(odb::dbChipNet* chip_net, utl::Logger* logger)
    : chip_net_(chip_net), logger_(logger)
{
}

IRNetwork3D::~IRNetwork3D() = default;

void IRNetwork3D::construct()
{
  interdie_connections_.clear();
  networks_.clear();

  for (uint32_t index = 0; index < chip_net_->getNumBumpInsts(); index++) {
    std::vector<odb::dbChipInst*> path;
    odb::dbChipBumpInst* bump_inst = chip_net_->getBumpInst(index, path);
    if (bump_inst == nullptr || path.empty()) {
      logger_->error(utl::PSM,
                     94,
                     "dbChipNet {} contains a bump with no chiplet path.",
                     chip_net_->getName());
    }

    odb::dbChipInst* chip_inst = path.back();
    odb::dbNet* net = bump_inst->getChipBump()->getNet();
    if (net == nullptr) {
      logger_->error(utl::PSM,
                     95,
                     "A bump on chiplet {} has no internal dbNet.",
                     chip_inst->getName());
    }

    const auto exists = std::ranges::find_if(
        networks_, [chip_inst, net](const ChipletNetwork& candidate) {
          return candidate.chip_inst == chip_inst && candidate.net == net;
        });
    if (exists == networks_.end()) {
      auto network = std::make_unique<IRNetwork>(net, logger_, false);
      networks_.push_back({chip_inst, net, std::move(network)});
    }
  }

  for (odb::dbChipRSeg* rseg : chip_net_->getChipRSegs()) {
    Node* source = findEndpoint(rseg->getSourceCapNode());
    Node* target = findEndpoint(rseg->getTargetCapNode());
    odb::dbChipBumpInst* source_bump
        = rseg->getSourceCapNode()->getChipBumpInst();
    odb::dbChipBumpInst* target_bump
        = rseg->getTargetCapNode()->getChipBumpInst();
    odb::dbChipInst* source_chip
        = source_bump->getChipRegionInst()->getChipInst();
    odb::dbChipInst* target_chip
        = target_bump->getChipRegionInst()->getChipInst();
    if (source_chip == target_chip) {
      logger_->error(utl::PSM,
                     106,
                     "dbChipRSeg on {} does not cross between chiplets.",
                     chip_net_->getName());
    }
    if (rseg->getResistance() <= 0.0) {
      logger_->error(utl::PSM,
                     96,
                     "dbChipRSeg on {} must have positive resistance.",
                     chip_net_->getName());
    }
    interdie_connections_.push_back(std::make_unique<FixedResistanceConnection>(
        source, target, rseg->getResistance()));
  }
}

IRNetwork3D::ChipletNetwork* IRNetwork3D::findNetwork(
    odb::dbChipBumpInst* bump_inst)
{
  if (bump_inst == nullptr) {
    logger_->error(
        utl::PSM, 97, "dbChipCapNode on {} has no bump.", chip_net_->getName());
  }

  odb::dbChipInst* chip_inst = bump_inst->getChipRegionInst()->getChipInst();
  odb::dbNet* net = bump_inst->getChipBump()->getNet();
  const auto network = std::ranges::find_if(
      networks_, [chip_inst, net](const ChipletNetwork& candidate) {
        return candidate.chip_inst == chip_inst && candidate.net == net;
      });
  if (network == networks_.end()) {
    logger_->error(utl::PSM,
                   98,
                   "Cannot find the chiplet PDN for an endpoint on {}.",
                   chip_net_->getName());
  }
  return &*network;
}

Node* IRNetwork3D::findEndpoint(odb::dbChipCapNode* cap_node)
{
  if (cap_node == nullptr) {
    logger_->error(utl::PSM,
                   99,
                   "dbChipRSeg on {} has no cap node.",
                   chip_net_->getName());
  }

  ChipletNetwork* chiplet = findNetwork(cap_node->getChipBumpInst());
  odb::dbBTerm* bterm = cap_node->getBTerm();
  BPinNode* node = chiplet->network->findBTermNode(bterm);
  if (node == nullptr) {
    logger_->error(utl::PSM,
                   100,
                   "Cannot map bump port {} on chiplet {} into its PDN.",
                   bterm == nullptr ? "<null>" : bterm->getName(),
                   chiplet->chip_inst->getName());
  }
  return node;
}

std::size_t IRNetwork3D::getNodeCount() const
{
  return getNodes().size();
}

std::size_t IRNetwork3D::getConnectionCount() const
{
  std::size_t count = interdie_connections_.size();
  for (const ChipletNetwork& chiplet : networks_) {
    count += chiplet.network->getConnections().size();
  }
  return count;
}

std::size_t IRNetwork3D::getBacksideBridgeConnectionCount() const
{
  std::size_t count = 0;
  for (const ChipletNetwork& chiplet : networks_) {
    for (const auto& connection : chiplet.network->getConnections()) {
      if (dynamic_cast<BridgeConnection*>(connection.get()) != nullptr) {
        count++;
      }
    }
  }
  return count;
}

IRNetwork3D::Nodes IRNetwork3D::getNodes() const
{
  Nodes nodes;
  for (Connection* connection : getConnections()) {
    nodes.insert(connection->getNode0());
    nodes.insert(connection->getNode1());
  }
  return nodes;
}

std::vector<Connection*> IRNetwork3D::getConnections() const
{
  std::vector<Connection*> connections;
  connections.reserve(getConnectionCount());
  for (const ChipletNetwork& chiplet : networks_) {
    for (const auto& connection : chiplet.network->getConnections()) {
      connections.push_back(connection.get());
    }
  }
  for (const auto& connection : interdie_connections_) {
    connections.push_back(connection.get());
  }
  return connections;
}

odb::PtrSet<odb::dbTechLayer> IRNetwork3D::getLayers() const
{
  odb::PtrSet<odb::dbTechLayer> layers;
  for (const ChipletNetwork& chiplet : networks_) {
    const auto chiplet_layers = chiplet.network->getLayers();
    layers.insert(chiplet_layers.begin(), chiplet_layers.end());
  }
  return layers;
}

Node* IRNetwork3D::findBTermNode(odb::dbChipInst* chip_inst,
                                 odb::dbBTerm* bterm) const
{
  if (chip_inst == nullptr || bterm == nullptr) {
    return nullptr;
  }

  const auto network = std::ranges::find_if(
      networks_, [chip_inst, bterm](const ChipletNetwork& candidate) {
        return candidate.chip_inst == chip_inst
               && candidate.net == bterm->getNet();
      });
  if (network == networks_.end()) {
    return nullptr;
  }
  return network->network->findBTermNode(bterm);
}

}  // namespace psm
