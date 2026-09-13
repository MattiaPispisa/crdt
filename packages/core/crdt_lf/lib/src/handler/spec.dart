import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/capabilities/formats_of.dart';

/// Builds a handler of type [T] for a document, from the spec describing it.
///
/// The spec is handed in rather than baked into the closure, so a
/// [HandlerSpec] can hold the only copy of it. Pass it straight to the
/// handler's `spec:` argument: that is what makes the handler declare its own
/// type on the document.
typedef HandlerBuilder<T extends Handler<dynamic>> = T Function(
  BaseCRDTDocument doc,
  String id,
  HandlerSpec<T> spec,
);

/// How to build one kind of handler, and what it reads.
///
/// Holds the three things a handler type needs to travel between peers: the
/// tag it is addressed by, how to build one, and the formats it reads. Written
/// once and passed around, so the tag cannot drift between the factory that
/// rebuilds a handler and the call that creates it.
///
/// A generic handler needs one, because its tag carries its type argument
/// (`CRDTRegisterHandler<bool>`) and `runtimeType.toString()` is minified away
/// in a Flutter web release build:
///
/// ```dart
/// // A built-in handler writes its own; only the tag is yours.
/// final done = CRDTRegisterHandler.spec<bool>('todo.done');
///
/// final flag = todo.child(doneKey, done);
/// ```
class HandlerSpec<T extends Handler<dynamic>> {
  /// Creates a spec for handlers addressed as [type].
  ///
  /// [formats] is what handlers of this kind read. It is what lets
  /// [CRDTDocument.describeBuildCapabilities] report the type before anything
  /// opens one, which is the whole point of stating it here: with no handler
  /// open there is nothing to read it off.
  ///
  /// For a built-in handler the class states it already — reach for
  /// `CRDTRegisterHandler.spec<bool>(tag)` instead of writing this out.
  const HandlerSpec(this.type, this._build, {required this.formats});

  /// A spec for a handler that already knows its own spec.
  ///
  /// Takes a plain [HandlerFactory], so a constructor tear-off works as is.
  /// That fits the built-in non-generic handlers, which hold their spec as a
  /// static and pass it to `super` themselves:
  ///
  /// ```dart
  /// static final spec = HandlerSpec.factory(
  ///   kTextHandlerType,
  ///   CRDTTextHandler.new,
  ///   formats: _formats,
  /// );
  /// ```
  ///
  /// Use the unnamed constructor for a handler that cannot: a generic one has
  /// no static to hold, because its tag carries the type argument. There the
  /// builder receives the spec and forwards it.
  ///
  /// The handler it builds has to report [type] as its [Handler.handlerType] —
  /// that is the tag a peer addresses it by, and [create] checks it.
  factory HandlerSpec.factory(
    String type,
    HandlerFactory factory, {
    required HandlerFormats formats,
  }) =>
      HandlerSpec(
        type,
        (doc, id, _) => factory(doc, id) as T,
        formats: formats,
      );

  /// The tag this handler is addressed by, as in [Handler.handlerType].
  ///
  /// Both peers have to use the same string, so make it a constant rather than
  /// something derived at run time.
  final String type;

  /// Builds one handler of this kind. Handed this spec, so it does not repeat
  /// what the spec already holds.
  ///
  /// Private: [create] is the way in, and it is what checks the handler it
  /// built against what this spec claims.
  final HandlerBuilder<T> _build;

  /// Builds the handler [id] on [doc].
  ///
  /// The way in for everything that creates from a spec, so what [build]
  /// produces is checked against [formats] once per call in debug: a spec that
  /// names kinds its handler does not decode tells a peer this build reads
  /// something it cannot, and the peer sends it.
  T create(BaseCRDTDocument doc, String id) {
    final created = _build(doc, id, this);

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

  /// The operation kinds and snapshot blob versions handlers of this kind
  /// read.
  final HandlerFormats formats;

  @override
  String toString() => 'HandlerSpec<$T>($type)';
}
