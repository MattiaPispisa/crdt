import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/document_state.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';

class TodoDocumentState extends DocumentState {
  TodoDocumentState._(CRDTDocument document, this._handler, Network network)
    : super(document, network);

  factory TodoDocumentState.create(PeerId author, {required Network network}) {
    final document = CRDTDocument(peerId: author);
    final handler = CRDTListHandler<String>(document, 'todo-list');
    return TodoDocumentState._(document, handler, network);
  }

  final CRDTListHandler<String> _handler;

  void addTodo(String todo) {
    _handler.insert(0, todo);
    notifyListeners();
  }

  void removeTodo(int index) {
    _handler.delete(index, 1);
    notifyListeners();
  }

  List<String> get todos => _handler.value;
}
