// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include "core/graph/onnx_protobuf.h"
#include "core/graph/graph.h"
#include "core/framework/ml_value.h"

namespace onnxruntime {

namespace graph_utils {

/** Checks if the operator's type, version, and domain of the given node match the given values. */
bool IsSupportedOptypeVersionAndDomain(const Node& node,
                                       const std::string& op_type,
                                       const std::initializer_list<ONNX_NAMESPACE::OperatorSetVersion>& versions,
                                       const std::string& domain = kOnnxDomainAlias);

/** Checks if the node has the same operator since version as the given one. */
bool MatchesOpSinceVersion(const Node& node, const std::initializer_list<ONNX_NAMESPACE::OperatorSetVersion>& versions);

/** Checks if the node has the same op set domain as the given one. */
bool MatchesOpSetDomain(const Node& node, const std::string& domain);

/** Returns true if the execution provider assigned to current node is present in the compatible providers list
    or if the compatible_providers list is empty. */
bool IsSupportedProvider(const Node& node,
                         const std::unordered_set<std::string>& compatible_providers);

/** Checks whether the node has a single input and a single output. The single input can be either the output of
    another node or an initializer, but not an implicit input from a parent subgraph. The single output can be 
    fed to multiple downstream operators, i.e., it can have multiple output edges. */
bool IsSingleInSingleOutNode(const Node& node);

/** Checks if the output at the specified index is input to downstream Nodes. */
bool IsOutputUsed(const Node& node, int index);

/** Returns true if the graph has the given input.*/
bool IsGraphInput(const Graph& graph, const NodeArg* input);

/** Checks if the given node has only constant inputs (initializers). */
bool AllNodeInputsAreConstant(const Graph& graph, const Node& node);

/** Gets the name of the incoming NodeArg with the specified index for the given node. */
const std::string& GetNodeInputName(const Node& node, int index);

/** Gets the name of the outgoing NodeArg with the specified index for the given node. */
const std::string& GetNodeOutputName(const Node& node, int index);

/** Returns the attribute of a Node with a given name. */
const ONNX_NAMESPACE::AttributeProto* GetNodeAttribute(const Node& node, const std::string& attr_name);

/** Retrieves the values for a repeated attribute of a node and place them to the values vector. */
template <typename T>
bool GetRepeatedNodeAttributeValues(const Node& node,
                                    const std::string& attr_name,
                                    std::vector<T>& values) {
  const auto* attr = graph_utils::GetNodeAttribute(node, attr_name);
  if (attr) {
    values = ONNX_NAMESPACE::RetrieveValues<T>(*attr);
    return true;
  }
  return false;
}

Status ForAllMutableSubgraphs(Graph& main_graph, std::function<Status(Graph&)> func);
Status ForAllSubgraphs(const Graph& main_graph, std::function<Status(const Graph&)> func);

/** Removes the given Node from the Graph and keeps Graph consistent by rebuilding needed connections.
    We support the removal of the Node as long as the following conditions hold:
    - There should be no implicit inputs.
    - Only one of the outputs is used by downstream operators (but it can have multiple output edges).
    - If the Node has a single incoming node (and possibly multiple initializers), we can remove the Node and
      connect its incoming node to its outgoing nodes.
    - If the Node has a single initializer as input, we remove the Node and feed the initializer as input to its
      output nodes. */
bool RemoveNode(Graph& graph, Node& node);

/** Removes all output edges from the given Node of the Graph. 
    This should probably be elevated to the Graph API eventually. */
size_t RemoveNodeOutputEdges(Graph& graph, Node& node);

/** Creates a TensorProto that will be used as an initializer to a node.
    @param[in] out_tensor the Tensor whose data and shape will be used to create the TensorProto.
    @param[in] node_arg the NodeArg of the Node for which the TensorProto will be used as an initializer.
    @param[out] tensor_proto the TensorProto. */
void BuildTensorProtoForInitializer(const Tensor& out_tensor, const NodeArg& node_arg,
                                    ONNX_NAMESPACE::TensorProto& tensor_proto);

}  // namespace graph_utils

}  // namespace onnxruntime
