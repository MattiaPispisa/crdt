import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/capabilities/formats_of.dart';

/// Builds the handler [id] on [doc].
///
/// A handler's constructor has exactly this shape, so a tear-off is the usual
/// way to name one: `CRDTFugueTextHandler.new`.
typedef HandlerBuilder<T extends Handler<dynamic>> = T Function(
  BaseCRDTDocument doc,
  String id,
);

/// {@template handler_spec}
/// A [HandlerSpec] names a **kind** of handler: the data it holds and the
/// operations that change it. Not one handler — a kind. Two ids of the same
/// kind share one:
///
/// ```dart
/// final todos = CRDTListHandler<Todo>(doc, 'todos', handlerType: 'todo-list');
/// final done = CRDTListHandler<Todo>(doc, 'done', handlerType: 'todo-list');
/// ```
///
/// Naming the kind is what lets another peer **build** it: a reference travels
/// as `(id, kind)`, so without the kind a peer holds an id it cannot turn into
/// anything. It is also what the manifest in a snapshot replays, and what a
/// sync layer compares to decide whether two builds can talk.
/// {@endtemplate}
///
/// Every handler answers one from [Handler.spec]. Write one by hand for a
/// handler of your own, or to declare a kind this peer never opens — see
/// [BaseCRDTDocument.register].
class HandlerSpec<T extends Handler<dynamic>> {
  /// Creates a spec for handlers addressed as [type].
  ///
  /// [formats] is what handlers of this kind read. Stating it is what lets
  /// [CRDTDocument.describeBuildCapabilities] report the kind before anything
  /// opens one: with no handler open there is nothing to read it off.
  const HandlerSpec(this.type, this._build, {required this.formats});

  /// {@template handler_type_tag}
  /// The name of the kind **on the wire**. It rides in every operation envelope
  /// and in every [HandlerRef]. When a peer decides which handler a change
  /// belongs to, this is the only thing it has to go on.
  ///
  /// It is **not** the handler's id. An id picks one handler; a tag says what
  /// kind that handler is, and many ids share one tag:
  ///
  /// ```dart
  /// // Two lists, one kind.
  /// CRDTListHandler<Todo>(doc, 'active',   handlerType: 'todo-list');
  /// CRDTListHandler<Todo>(doc, 'archived', handlerType: 'todo-list');
  /// ```
  ///
  /// **Choosing one.** Any string, as long as it is a constant you control and
  /// every peer spells it the same way. A literal in your code is fine; the tag
  /// of a Dart type is not, because it is not yours to keep stable. Write it
  /// once, in a builder, and pass that around:
  ///
  /// ```dart
  /// CRDTListHandler<Todo> newTodoList(BaseCRDTDocument doc, String id) =>
  ///     CRDTListHandler<Todo>(doc, id, handlerType: 'todo-list');
  /// ```
  ///
  /// **Why it is asked for.** A generic handler cannot fall back on its Dart
  /// type: that carries the type argument (`CRDTListHandler<Todo>`), and
  /// dart2js rewrites it in a Flutter web release build. The same code would
  /// route changes on the VM and stop routing them on the web. A non-generic
  /// handler has no such problem, so it fixes its own tag and asks nothing.
  ///
  /// **What a wrong one costs.** Two peers that spell it differently hold two
  /// kinds that never meet: changes reach no handler and a nested reference
  /// resolves to `null`. Nothing throws — one side simply stops seeing the
  /// other's edits. Changing it later has the same effect on the data already
  /// written, so treat it as part of the wire format.
  /// {@endtemplate}
  final String type;

  /// Builds one handler of this kind.
  ///
  /// Private: [create] is the way in, and it is what checks the handler it
  /// built against what this spec claims.
  final HandlerBuilder<T> _build;

  /// The operation kinds and snapshot blob versions handlers of this kind read.
  final HandlerFormats formats;

  /// Builds the handler [id] on [doc].
  ///
  /// Prefer [BaseCRDTDocument.handler]: this throws
  /// [HandlerAlreadyRegisteredException] when [id] is already open, where that
  /// one hands back the handler already there. Reach for this only when the id
  /// is fresh.
  ///
  /// What the builder produces is checked against [type] and [formats] once per
  /// call in debug. A spec that names kinds its handler cannot decode tells a
  /// peer this build reads them, and the peer sends them.
  ///
  /// The checks run after the handler is built, and a handler registers itself
  /// as it is constructed. So a spec that fails them leaves that handler on
  /// [doc]. In debug that is a crash either way.
  T create(BaseCRDTDocument doc, String id) {
    final created = _build(doc, id);

    assert(
      formatsOf(created) == formats,
      'The spec for $type declares $formats but builds a handler reading '
      '${formatsOf(created)}.',
    );
    assert(
      created.handlerType == type,
      'The spec for $type builds a handler tagged ${created.handlerType}, '
      'so a peer addressing $type would not find it.',
    );

    return created;
  }

  /// Two specs are the same when they claim the same [type] and the same
  /// [formats].
  ///
  /// Value equality, because a spec is minted wherever a tag is: every
  /// `CRDTListHandler<Todo>(doc, id, handlerType: 'todos')` builds a fresh one,
  /// and they all describe the same kind. Comparing by identity would make two
  /// handlers of one kind look like a conflict.
  ///
  /// The builder is **not** compared — two closures are never equal, and it is
  /// what carries a value codec. So two specs that share a tag and differ only
  /// in the codec they capture compare equal here, and the document keeps
  /// whichever arrived first. One tag has to mean one wire format; this cannot
  /// catch a build that breaks that.
  @override
  bool operator ==(Object other) =>
      other is HandlerSpec && other.type == type && other.formats == formats;

  @override
  int get hashCode => Object.hash(type, formats);

  @override
  String toString() => 'HandlerSpec<$T>($type)';
}
