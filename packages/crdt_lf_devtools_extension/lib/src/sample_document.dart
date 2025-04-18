import 'package:crdt_lf/crdt_lf.dart';

/// Utility class to create sample CRDT documents for demonstration
class SampleDocument {
  /// Creates a list of sample CRDT documents with different operations
  static List<CRDTDocument> createSampleDocuments() {
    return [
      _createTextDocument(),
      _createComplexDocument(),
    ];
  }

  /// Creates a sample document with text operations
  static CRDTDocument _createTextDocument() {
    final doc = CRDTDocument();
    final textHandler = CRDTTextHandler(doc, 'sample-text');
    
    // Add some operations to create a DAG
    textHandler.insert(0, 'Hello');
    textHandler.insert(5, ' World');
    textHandler.delete(0, 1);
    textHandler.insert(9, '!');
    
    return doc;
  }

  /// Creates a more complex document with multiple operations
  static CRDTDocument _createComplexDocument() {
    final doc = CRDTDocument();
    
    // Text handler
    final textHandler = CRDTTextHandler(doc, 'complex-text');
    textHandler.insert(0, 'Complex CRDT');
    textHandler.insert(12, ' Document');
    textHandler.delete(8, 4);
    textHandler.insert(8, 'Example');
    
    // List handler
    final listHandler = CRDTListHandler<String>(doc, 'sample-list');
    listHandler.insert(0, 'Item 1');
    listHandler.insert(1, 'Item 2');
    listHandler.insert(2, 'Item 3');
    listHandler.delete(1, 1);
    listHandler.insert(1, 'New Item');
    
    return doc;
  }
} 