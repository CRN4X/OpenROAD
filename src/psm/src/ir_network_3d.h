// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#pragma once

#include <cstddef>
#include <memory>
#include <set>
#include <vector>

#include "connection.h"
#include "node.h"
#include "odb/PtrSetMap.h"
#include "odb/db.h"

namespace utl {
class Logger;
}

namespace psm {

class IRNetwork;

class IRNetwork3D
{
 public:
  // Pointer identity keeps nodes from overlapping chiplet-local coordinates
  // distinct in the combined network.
  using Nodes = std::set<Node*>;

  IRNetwork3D(odb::dbChipNet* chip_net, utl::Logger* logger);
  ~IRNetwork3D();

  void construct();

  odb::dbChipNet* getChipNet() const { return chip_net_; }
  std::size_t getChipletNetworkCount() const { return networks_.size(); }
  std::size_t getInterDieConnectionCount() const
  {
    return interdie_connections_.size();
  }
  std::size_t getNodeCount() const;
  std::size_t getConnectionCount() const;
  std::size_t getBacksideBridgeConnectionCount() const;

  Nodes getNodes() const;
  std::vector<Connection*> getConnections() const;
  odb::PtrSet<odb::dbTechLayer> getLayers() const;
  Node* findBTermNode(odb::dbChipInst* chip_inst, odb::dbBTerm* bterm) const;

  const Connections& getInterDieConnections() const
  {
    return interdie_connections_;
  }

 private:
  struct ChipletNetwork
  {
    odb::dbChipInst* chip_inst;
    odb::dbNet* net;
    std::unique_ptr<IRNetwork> network;
  };

  ChipletNetwork* findNetwork(odb::dbChipBumpInst* bump_inst);
  Node* findEndpoint(odb::dbChipCapNode* cap_node);

  odb::dbChipNet* chip_net_;
  utl::Logger* logger_;
  std::vector<ChipletNetwork> networks_;
  Connections interdie_connections_;
};

}  // namespace psm
