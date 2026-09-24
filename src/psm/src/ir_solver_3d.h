// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#pragma once

#include <cstddef>
#include <map>
#include <memory>
#include <optional>
#include <vector>

#include "Eigen/Core"
#include "Eigen/Sparse"
#include "connection.h"
#include "ir_network_3d.h"

namespace utl {
class Logger;
}

namespace psm {

class IRSolver3D
{
 public:
  using ConductanceMatrix = Eigen::SparseMatrix<Connection::Conductance>;
  using Current = double;
  using CurrentVector = Eigen::VectorXd;
  using Voltage = double;
  using VoltageVector = Eigen::VectorXd;

  IRSolver3D(odb::dbChipNet* chip_net, utl::Logger* logger);

  void build();
  bool check() const;
  void addCurrentLoad(odb::dbChipInst* chip_inst,
                      odb::dbBTerm* bterm,
                      Current current);
  bool checkCurrentVector() const;
  void addVoltageSource(odb::dbChipInst* chip_inst,
                        odb::dbBTerm* bterm,
                        Voltage voltage);
  bool solve();
  bool checkSolution() const;
  bool isConnected() const;
  bool sourcesCoverAllComponents() const;

  IRNetwork3D* getNetwork() const { return network_.get(); }
  std::size_t getNodeCount() const { return node_index_.size(); }
  std::size_t getNonZeroCount() const
  {
    return static_cast<std::size_t>(g_matrix_.nonZeros());
  }
  const ConductanceMatrix& getConductanceMatrix() const { return g_matrix_; }
  const CurrentVector& getCurrentVector() const { return j_vector_; }
  std::size_t getCurrentLoadCount() const { return current_loads_.size(); }
  std::size_t getNonZeroCurrentCount() const;
  Current getTotalCurrent() const { return j_vector_.sum(); }
  std::size_t getVoltageSourceCount() const { return voltage_sources_.size(); }
  bool hasSolution() const
  {
    return getNodeCount() > 0
           && voltage_vector_.size()
                  == static_cast<Eigen::Index>(getNodeCount());
  }
  const VoltageVector& getVoltageVector() const { return voltage_vector_; }
  std::optional<Voltage> getVoltage(odb::dbChipInst* chip_inst,
                                    odb::dbBTerm* bterm) const;

 private:
  struct CurrentLoad
  {
    odb::dbChipInst* chip_inst;
    odb::dbBTerm* bterm;
    Current current;
  };

  struct VoltageSource
  {
    odb::dbChipInst* chip_inst;
    odb::dbBTerm* bterm;
    Voltage voltage;
  };

  Connection::ResistanceMap getResistanceMap() const;
  void buildConductanceMatrix();
  void buildCurrentVector();
  bool buildSourceMap(std::map<std::size_t, Voltage>& sources) const;

  utl::Logger* logger_;
  std::unique_ptr<IRNetwork3D> network_;
  std::map<Node*, std::size_t> node_index_;
  ConductanceMatrix g_matrix_;
  std::vector<CurrentLoad> current_loads_;
  CurrentVector j_vector_;
  std::vector<VoltageSource> voltage_sources_;
  VoltageVector voltage_vector_;
};

}  // namespace psm
