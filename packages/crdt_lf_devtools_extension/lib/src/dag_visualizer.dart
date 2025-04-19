import 'package:devtools_app_shared/service.dart';
import 'package:flutter/material.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'dag_view.dart';
import 'dart:async';
import 'dart:convert';
import 'package:vm_service/vm_service.dart';

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
  List<Map<String, dynamic>> _documentInfos = [];
  Map<String, List<String>> _handlersPerDocument = {};
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _refreshTimer;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _loadDocumentsFromApp();
    _setupEventSubscription();
    // Set up periodic refresh
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadDocumentsFromApp(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _setupEventSubscription() {
    _eventSubscription =
        serviceManager.service?.onExtensionEvent.listen((event) {
      if (event.kind == 'crdt_lf:documents:created' ||
          event.kind == 'crdt_lf:document:changed') {
        _loadDocumentsFromApp();
      }
    });
  }

  Future<void> _loadDocumentsFromApp() async {
    if (!serviceManager.hasConnection) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _documents = [];
        _documentInfos = [];
        _handlersPerDocument = {};
        _selectedDocument = null;
        _selectedHandlerId = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Ottieni l'isolate selezionato
      final isolate = serviceManager
          .connectedApp?.serviceManager?.isolateManager.selectedIsolate.value;

      if (isolate == null) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        return;
      }

      final eval = EvalOnDartLibrary(
        'package:crdt_lf/src/devtools/devtools.dart',
        serviceManager.service!,
        serviceManager: serviceManager,
      );

      final isAlive = Disposable();

      // Ottieni la lista dei documenti
      final result =
          await eval.evalInstance('TrackedDocument.all', isAlive: isAlive);

      result.elements?.cast<InstanceRef>().map((element) {

      });

      print("result: ${result.elements}");

      try {
        // Salviamo le informazioni sui documenti
        _documentInfos = [];
        _documents = [];
        _handlersPerDocument = {};

        // Ottieni il numero di documenti
        final countResult =
            await eval.eval('TrackedDocument.all.length', isAlive: isAlive);
        if (countResult == null) {
          print("Impossibile ottenere il numero di documenti");
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
          return;
        }

        print("countResult: ${countResult.valueAsString}");

        final count = int.tryParse(countResult.valueAsString!);
        if (count == null) {
          print("Numero di documenti non valido");
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
          return;
        }

        // Itera sui documenti
        for (var i = 0; i < count; i++) {
          // Ottieni le informazioni del documento
          final docIdResult = await eval
              .eval('TrackedDocument.all[$i].document.id', isAlive: isAlive);
          print("docIdResult: ${docIdResult?.valueAsString}");
          final changeCountResult = await eval.eval(
              'TrackedDocument.all[$i].document.changes.length',
              isAlive: isAlive);
          final frontierCountResult = await eval.eval(
              'TrackedDocument.all[$i].document.frontier.length',
              isAlive: isAlive);
          final handlersResult = await eval.eval(
              'TrackedDocument.all[$i].document.handlers.keys.toList()',
              isAlive: isAlive);

          if (docIdResult == null ||
              changeCountResult == null ||
              frontierCountResult == null ||
              handlersResult == null) {
            continue;
          }

          final docId = docIdResult.toString();
          final changeCount = int.tryParse(changeCountResult.toString());
          final frontierCount = int.tryParse(frontierCountResult.toString());
          final handlers =
              List<String>.from(json.decode(handlersResult.toString()));

          if (changeCount == null || frontierCount == null) {
            continue;
          }

          // Crea un nuovo documento per la visualizzazione
          final doc = CRDTDocument();
          _documents.add(doc);

          // Estrai le informazioni sugli handler
          if (handlers.isEmpty) {
            // Se non ci sono gestori specifici, aggiungiamo handler di default
            handlers.add('Text Handler');
            handlers.add('List Handler');
          }

          _handlersPerDocument[docId] = handlers;
          _documentInfos.add({
            'id': docId,
            'changeCount': changeCount,
            'frontierCount': frontierCount,
            'handlers': handlers,
          });
        }

        setState(() {
          if (_documents.isNotEmpty) {
            _selectedDocument = _documents.first;

            // Seleziona il primo handler disponibile per il documento
            final docId = _documentInfos.first['id'] as String;
            final handlers = _handlersPerDocument[docId] ?? [];
            _selectedHandlerId = handlers.isNotEmpty ? handlers.first : null;
          } else {
            _selectedDocument = null;
            _selectedHandlerId = null;
          }
          _isLoading = false;
          _hasError = false;
        });
      } catch (e) {
        print("Errore nel parsing dei documenti: $e");
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      print("Errore nella comunicazione con l'app: $e");
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return const Center(child: Text('Error loading documents'));
    }

    if (_documents.isEmpty) {
      return const Center(child: Text('No documents available'));
    }

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _selectedDocument != null && _selectedHandlerId != null
              ? DAGView(
                  document: _selectedDocument!, handleId: _selectedHandlerId!)
              : const Center(
                  child: Text('Select a document and handler to visualize')),
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
          _buildDocumentDropdown(),
          const SizedBox(width: 24),
          const Text('Handler:'),
          const SizedBox(width: 12),
          _buildHandlerDropdown(),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            onPressed: _loadDocumentsFromApp,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentDropdown() {
    return DropdownButton<int>(
      value: _selectedDocument != null
          ? _documents.indexOf(_selectedDocument!)
          : null,
      hint: const Text('Select a document'),
      onChanged: (index) {
        if (index != null) {
          setState(() {
            _selectedDocument = _documents[index];

            // Ottieni l'ID del documento dalle informazioni
            String docId;
            if (_documentInfos.isNotEmpty && index < _documentInfos.length) {
              docId = _documentInfos[index]['id'] as String;
            } else {
              docId = 'Document ${index + 1}';
            }

            // Ottieni gli handler per questo documento
            final handlers = _handlersPerDocument[docId] ?? [];
            _selectedHandlerId = handlers.isNotEmpty ? handlers.first : null;
          });
        }
      },
      items: List.generate(_documents.length, (index) {
        // Mostra informazioni sul documento se disponibili
        String label;
        if (_documentInfos.isNotEmpty && index < _documentInfos.length) {
          final info = _documentInfos[index];
          final changeCount = info['changeCount'] as int;
          label = 'Doc ${index + 1} (${changeCount} changes)';
        } else {
          label = 'Document ${index + 1}';
        }

        return DropdownMenuItem<int>(
          value: index,
          child: Text(label),
        );
      }),
    );
  }

  Widget _buildHandlerDropdown() {
    if (_selectedDocument == null) {
      return const SizedBox();
    }

    final docIndex = _documents.indexOf(_selectedDocument!);

    // Ottieni l'ID del documento per recuperare gli handler
    String docId;
    if (_documentInfos.isNotEmpty && docIndex < _documentInfos.length) {
      docId = _documentInfos[docIndex]['id'] as String;
    } else {
      docId = 'Document ${docIndex + 1}';
    }

    final handlers = _handlersPerDocument[docId] ?? [];

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
