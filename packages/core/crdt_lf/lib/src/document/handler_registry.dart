part of 'document.dart';

/// The open handlers of a document, the kinds it can build, and the index
/// that routes a change to its handler.
///
/// [add], [remove] and [clear] are the only writes to the open handlers, and
/// each moves the routing index with them: the index always holds exactly the
/// open handlers.
final class _HandlerRegistry {
  _HandlerRegistry()
      : _byId = {},
        _byPrefix = {},
        specs = {};

  final Map<String, Handler<dynamic>> _byId;

  /// The open handlers keyed by the hash of their envelope prefix.
  final Map<int, List<Handler<dynamic>>> _byPrefix;

  /// How to build a handler of a kind, keyed by [HandlerSpec.type].
  final Map<String, HandlerSpec<Handler<dynamic>>> specs;

  /// The open handler with [id]; `null` when none is open.
  Handler<dynamic>? operator [](String id) => _byId[id];

  bool get isEmpty => _byId.isEmpty;

  Iterable<Handler<dynamic>> get values => _byId.values;

  /// A read-only view of the open handlers, keyed by id.
  Map<String, Handler<dynamic>> get view => UnmodifiableMapView(_byId);

  /// Opens [handler], and declares its kind when none is declared yet.
  ///
  /// Throws [HandlerAlreadyRegisteredException] when its id is open.
  void add(Handler<dynamic> handler) {
    if (_byId.containsKey(handler.id)) {
      throw HandlerAlreadyRegisteredException(
        'Handler with ID ${handler.id} already registered',
      );
    }
    _byId[handler.id] = handler;
    (_byPrefix[fnv1a32(handler._envelopePrefix)] ??= []).add(handler);

    final spec = handler._instanceSpec;
    assert(
      HandlerFormats.of(handler) == spec.formats,
      '${spec.type} declares ${spec.formats} but reads '
      '${HandlerFormats.of(handler)}. A peer is told this build reads '
      'something it cannot decode, and sends it.',
    );
    assert(
      specs[spec.type] == null || specs[spec.type] == spec,
      'Two specs claim the tag ${spec.type} and read different formats. '
      'One tag has to mean one wire format.',
    );
    // `putIfAbsent`: an explicit `register` made earlier wins.
    specs.putIfAbsent(spec.type, () => spec);
  }

  Handler<dynamic>? remove(String id) {
    final handler = _byId.remove(id);
    if (handler == null) {
      return null;
    }
    final key = fnv1a32(handler._envelopePrefix);
    final candidates = _byPrefix[key]!..remove(handler);
    if (candidates.isEmpty) {
      _byPrefix.remove(key);
    }
    return handler;
  }

  void clear() {
    _byId.clear();
    _byPrefix.clear();
  }

  /// The open handler [payload] is addressed to; `null` when none is open.
  ///
  /// Decodes nothing, so the apply path stays free of envelope decodes.
  Handler<dynamic>? forPayload(Uint8List payload) {
    final int end;
    try {
      final type = UVarint.read(payload, offset: 0);
      final id = UVarint.read(payload, offset: type.nextOffset + type.value);
      end = id.nextOffset + id.value;
    } on FormatException {
      return null;
    }
    // +1 for the kind byte that follows the prefix.
    if (end + 1 > payload.length) {
      return null;
    }

    final candidates = _byPrefix[fnv1a32(payload, end: end)];
    if (candidates == null) {
      return null;
    }
    for (final candidate in candidates) {
      final prefix = candidate._envelopePrefix;
      if (prefix.length == end && startsWithBytes(payload, prefix)) {
        return candidate;
      }
    }
    return null;
  }

  /// The handler [spec] describes under [id] on [document], or the one already
  /// open there.
  ///
  /// Throws [HandlerAlreadyRegisteredException] when [id] is open as another
  /// kind.
  T open<T extends Handler<dynamic>>(
    BaseCRDTDocument document,
    HandlerSpec<T> spec,
    String id,
  ) {
    final existing = _byId[id];
    if (existing != null) {
      if (existing is T && existing.handlerType == spec.type) {
        return existing;
      }
      throw HandlerAlreadyRegisteredException(
        'Handler with ID $id is a ${existing.handlerType}, '
        'not a ${spec.type}',
      );
    }
    return spec.create(document, id);
  }

  /// The handler [ref] points at on [document]: the open one, or one built
  /// from the kind it names; `null` when that kind is unknown.
  Handler<dynamic>? resolve(BaseCRDTDocument document, HandlerRef ref) {
    final existing = _byId[ref.id];
    if (existing != null) {
      return existing;
    }
    return specs[ref.type]?.create(document, ref.id);
  }

  /// Builds on [document] every handler that [changes] or [manifest] name and
  /// this registry can build, then [materializeReachable].
  void reconstruct(
    BaseCRDTDocument document, {
    required Iterable<Change> changes,
    required Map<String, String> manifest,
  }) {
    final discovered = <String, String>{};
    for (final change in changes) {
      try {
        final env = OperationEnvelopeCodec.decode(change.payloadBytes());
        discovered[env.handlerId] = env.handlerType;
      } catch (_) {
        // Ignore changes whose envelope cannot be decoded.
      }
    }
    discovered.addAll(manifest);

    for (final entry in discovered.entries) {
      if (!_byId.containsKey(entry.key) && !document.isDeleted(entry.key)) {
        specs[entry.value]?.create(document, entry.key);
      }
    }

    materializeReachable(document);
  }

  /// The open handlers no open container references.
  List<Handler<dynamic>> roots() {
    final referenced = <String>{};
    for (final handler in _byId.values) {
      if (handler is ContainerHandler) {
        for (final ref in (handler as ContainerHandler).childRefs()) {
          referenced.add(ref.id);
        }
      }
    }
    return _byId.values
        .where((handler) => !referenced.contains(handler.id))
        .toList();
  }

  /// Builds on [document] every handler reachable from the open containers,
  /// following their references to a fixed point.
  ///
  /// A child is built only when something reads it, so an open handler can
  /// reference one that is not open yet — and that a snapshot would miss.
  void materializeReachable(BaseCRDTDocument document) {
    final queue = Queue<Handler<dynamic>>.of(_byId.values);
    final seen = <String>{};
    while (queue.isNotEmpty) {
      final handler = queue.removeFirst();
      if (!seen.add(handler.id)) {
        continue;
      }
      if (handler is ContainerHandler) {
        for (final ref in (handler as ContainerHandler).childRefs()) {
          final child = document.resolveHandler(ref);
          if (child != null && !seen.contains(child.id)) {
            queue.add(child);
          }
        }
      }
    }
  }

  /// The `{id: type}` manifest of the open handlers.
  Map<String, String> manifest() => {
        for (final handler in _byId.values) handler.id: handler.handlerType,
      };

  /// The `{id: type}` manifest [snapshot] carries; empty when there is no
  /// snapshot or it predates the manifest.
  static Map<String, String> manifestOf(Snapshot? snapshot) {
    final blob = snapshot?.data[SnapshotRecords.manifestKey];
    if (blob == null) {
      return const {};
    }
    return SnapshotRecords.decodeManifest(blob);
  }
}
