import 'package:crdt_lf/crdt_lf.dart';

/// The handler types this package ships, and how to rebuild each one.
///
/// Consulted by every [CRDTDocument] rather than registered by the app: the
/// classes are compiled into this build, so it really can read them and there
/// is nothing for an app to declare. It is what lets a peer resolve a nested
/// child of one of these types without having opened one first — the case an
/// app cannot cover, because a received child is by definition a handler it
/// never created.
///
/// Read on the resolve paths only, never on the change apply path. A document
/// that registered nothing keeps an empty `_specs`, which is the check that
/// keeps applying a change free of an envelope decode.
///
/// A generic handler is absent on purpose: its tag carries the type argument,
/// so only the app can name it. See `CRDTListHandler.spec`.
final Map<String, HandlerSpec<Handler<dynamic>>> kBuiltInHandlerSpecs = {
  for (final spec in <HandlerSpec<Handler<dynamic>>>[
    CRDTTextHandler.spec,
    CRDTFugueTextHandler.spec,
    CRDTMapRefHandler.spec,
    CRDTListRefHandler.spec,
    CRDTMovableListRefHandler.spec,
  ])
    spec.type: spec,
};
