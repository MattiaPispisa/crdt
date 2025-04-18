import 'package:flutter/material.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'dag_view.dart';
import 'sample_document.dart';

/// A widget that visualizes the DAG of a CRDT document
class DAGVisualizer extends StatefulWidget {
  const DAGVisualizer({Key? key}) : super(key: key);

  @override
  State<DAGVisualizer> createState() => _DAGVisualizerState();
}

class _DAGVisualizerState extends State<DAGVisualizer> {
  CRDTDocument? _selectedDocument;
  String? _selectedHandlerId;
  List<CRDTDocument> _documents = [];
  Map<String, List<String>> _handlersPerDocument = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSampleDocuments();
  }

  void _loadSampleDocuments() {
    // Generate sample documents for demonstration
    setState(() {
      _isLoading = true;
    });

    // Create sample documents with different handlers for demonstration
    final documents = SampleDocument.createSampleDocuments();
    
    final handlersPerDoc = <String, List<String>>{};
    for (var i = 0; i < documents.length; i++) {
      handlersPerDoc['Document ${i + 1}'] = ['Text Handler', 'List Handler', 'Counter Handler'];
    }
    
    setState(() {
      _documents = documents;
      _handlersPerDocument = handlersPerDoc;
      _selectedDocument = documents.isNotEmpty ? documents.first : null;
      _selectedHandlerId = handlersPerDoc.values.isNotEmpty && handlersPerDoc.values.first.isNotEmpty 
          ? handlersPerDoc.values.first.first 
          : null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_documents.isEmpty) {
      return const Center(child: Text('No documents available'));
    }

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _selectedDocument != null && _selectedHandlerId != null
              ? DAGView(document: _selectedDocument!, handleId: _selectedHandlerId!)
              : const Center(child: Text('Select a document and handler to visualize')),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const Text('Document:'),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _selectedDocument != null ? _documents.indexOf(_selectedDocument!) : null,
            hint: const Text('Select a document'),
            onChanged: (index) {
              if (index != null) {
                setState(() {
                  _selectedDocument = _documents[index];
                  final docName = 'Document ${index + 1}';
                  final handlers = _handlersPerDocument[docName] ?? [];
                  _selectedHandlerId = handlers.isNotEmpty ? handlers.first : null;
                });
              }
            },
            items: List.generate(_documents.length, (index) {
              return DropdownMenuItem<int>(
                value: index,
                child: Text('Document ${index + 1}'),
              );
            }),
          ),
          const SizedBox(width: 24),
          const Text('Handler:'),
          const SizedBox(width: 12),
          _buildHandlerDropdown(),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            onPressed: _loadSampleDocuments,
          ),
        ],
      ),
    );
  }

  Widget _buildHandlerDropdown() {
    if (_selectedDocument == null) {
      return const SizedBox();
    }

    final docIndex = _documents.indexOf(_selectedDocument!);
    final docName = 'Document ${docIndex + 1}';
    final handlers = _handlersPerDocument[docName] ?? [];

    return DropdownButton<String>(
      value: _selectedHandlerId,
      hint: const Text('Select a handler'),
      onChanged: (handlerId) {
        if (handlerId != null) {
          setState(() {
            _selectedHandlerId = handlerId;
          });
        }
      },
      items: handlers.map((handler) {
        return DropdownMenuItem<String>(
          value: handler,
          child: Text(handler),
        );
      }).toList(),
    );
  }
} 