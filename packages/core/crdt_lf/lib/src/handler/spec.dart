import 'package:crdt_lf/crdt_lf.dart';

/// Builds the handler [id] on [doc].
typedef HandlerBuilder<T extends Handler<dynamic>> = T Function(
  BaseCRDTDocument doc,
  String id,
);

/// {@template handler_spec}
/// Names a **kind** of handler: the data it holds and the operations that
/// change it. Not one handler — a kind, which many ids share.
/// {@endtemplate}
///
/// A peer that receives a reference holds `(id, kind)`, so the kind is what
/// lets it build the handler. Every handler answers one from [Handler.spec];
/// write one by hand for a handler of your own, or to declare a kind this peer
/// never opens — see [BaseCRDTDocument.register].
class HandlerSpec<T extends Handler<dynamic>> {
  /// Creates a spec for handlers addressed as [type].
  const HandlerSpec(this.type, this._build, {required this.formats});

  /// {@template handler_type_tag}
  /// The name of this kind **on the wire**: it travels in every operation
  /// envelope and in every [HandlerRef], so every peer has to spell it the
  /// same way. Make it a constant of your own.
  ///
  /// It is not the handler's id. An id picks one handler; this says what kind
  /// that handler is.
  /// {@endtemplate}
  final String type;

  /// Builds one handler of this kind.
  final HandlerBuilder<T> _build;

  /// What handlers of this kind read.
  ///
  /// Stated rather than derived, so [CRDTDocument.describeBuildCapabilities]
  /// can report the kind before anything opens one.
  final HandlerFormats formats;

  /// Builds the handler [id] on [doc].
  ///
  /// Prefer [BaseCRDTDocument.handler], which hands back the handler already
  /// open under [id]; this throws [HandlerAlreadyRegisteredException] instead.
  T create(BaseCRDTDocument doc, String id) {
    final created = _build(doc, id);

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
  /// The builder is not compared: two specs that share a tag and differ only in
  /// the value codec they build with compare equal.
  @override
  bool operator ==(Object other) =>
      other is HandlerSpec && other.type == type && other.formats == formats;

  @override
  int get hashCode => Object.hash(type, formats);

  @override
  String toString() => 'HandlerSpec<$T>($type)';
}
