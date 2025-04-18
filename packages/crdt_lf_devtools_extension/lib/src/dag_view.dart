import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:graphview/graphview.dart';

/// A widget that visualizes the DAG of a CRDT document
class DAGView extends StatefulWidget {
  /// Creates a new DAG view
  const DAGView({
    Key? key,
    required this.document,
    required this.handleId,
  }) : super(key: key);

  /// The document to visualize
  final CRDTDocument document;

  /// The ID of the handler to visualize
  final String handleId;

  @override
  State<DAGView> createState() => _DAGViewState();
}

class _DAGViewState extends State<DAGView> {
  final Graph graph = Graph()..isTree = false;
  late BuchheimWalkerConfiguration builder;
  Map<String, Node> nodeMap = {};

  @override
  void initState() {
    super.initState();
    _configureLayout();
    _buildGraph();
  }

  @override
  void didUpdateWidget(DAGView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.handleId != widget.handleId) {
      _buildGraph();
    }
  }

  void _configureLayout() {
    builder = BuchheimWalkerConfiguration()
      ..siblingSeparation = 100
      ..levelSeparation = 150
      ..subtreeSeparation = 150
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM;
  }

  void _buildGraph() {
    setState(() {
      graph.nodes.clear();
      graph.edges.clear();
      nodeMap.clear();

      // Since we can't directly access the internal DAG of the document,
      // we'll create a simulated DAG for visualization purposes
      _buildSimulatedDAG();
    });
  }

  void _buildSimulatedDAG() {
    // Create a root node
    final rootNode = Node.Id('root');
    nodeMap['root'] = rootNode;

    // Create nodes based on the changes in the document
    // In a real implementation, we would access the actual DAG
    // but since it's private, we'll create a simulated visualization

    final changes = widget.document.exportChanges();

    if (changes.isEmpty) {
      return;
    }

    // Create nodes for each change
    for (var i = 0; i < changes.length; i++) {
      final change = changes[i];
      final nodeId = 'change-${change.id}';
      final node = Node.Id(nodeId);
      nodeMap[nodeId] = node;

      // Connect the node to its dependencies
      if (change.deps.isEmpty) {
        // If no dependencies, connect to root
        graph.addEdge(rootNode, node);
      } else {
        // Connect to dependencies
        for (final depId in change.deps) {
          final depNodeId = 'change-$depId';
          if (nodeMap.containsKey(depNodeId)) {
            graph.addEdge(nodeMap[depNodeId]!, node);
          } else {
            // If dependency not found (might be filtered out), connect to root
            graph.addEdge(rootNode, node);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (graph.nodes.isEmpty) {
      return const Center(
        child: Text('No operations to display'),
      );
    }

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.1,
      maxScale: 5.0,
      child: GraphView(
        graph: graph,
        algorithm: BuchheimWalkerAlgorithm(builder, TreeEdgeRenderer(builder)),
        paint: Paint()
          ..color = Colors.green
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
        builder: (Node node) {
          return _buildNodeWidget(node);
        },
      ),
    );
  }

  Widget _buildNodeWidget(Node node) {
    // Get the ID from the node
    final id = node.key?.value?.toString() ?? 'Unknown';

    // Format the node differently based on its type
    if (id == 'root') {
      return _buildRootNode();
    } else if (id.startsWith('change-')) {
      return _buildChangeNode(id.substring(7)); // Remove 'change-' prefix
    } else {
      return _buildGenericNode(id);
    }
  }

  Widget _buildRootNode() {
    return Card(
      elevation: 4,
      color: Colors.orange[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: const Text(
          'ROOT',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildChangeNode(String opId) {
/*     final String opType = _getOperation(change);
    final Color backgroundColor = _getColorForOperationType(opType);
 */
    return Card(
      elevation: 4,
      color: Colors.blue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              opId,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getShortId(opId),
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericNode(String id) {
    return Card(
      elevation: 4,
      color: Colors.grey[200],
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Text(id),
      ),
    );
  }

  String _getOperation(Change change) {
    // Extract operation type from change
    // This is a simplification; in a real implementation,
    // you would extract more detailed information
    try {
      return jsonDecode(change.payload);
    } catch (e) {
      return 'Unknown';
    }
  }

  Color _getColorForOperationType(String opType) {
    switch (opType) {
      case 'Insert':
        return Colors.green[100]!;
      case 'Delete':
        return Colors.red[100]!;
      default:
        return Colors.blue[100]!;
    }
  }

  String _getShortId(String id) {
    // Truncate long IDs for display
    if (id.length > 20) {
      return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
    }
    return id;
  }
}
