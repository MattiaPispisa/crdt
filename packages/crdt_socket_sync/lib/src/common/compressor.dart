import 'package:crdt_socket_sync/src/common/codec.dart';

/// Interface for data compression
abstract class Compressor {
  /// Compress data
  List<int> compress(List<int> data);

  /// Decompress data
  List<int> decompress(List<int> data);
}

/// No compression implementation
class NoCompression implements Compressor {
  /// Private constructor
  const NoCompression._();

  /// Singleton
  static const NoCompression instance = NoCompression._();

  @override
  List<int> compress(List<int> data) => data;

  @override
  List<int> decompress(List<int> data) => data;
}

/// Codec for messages with optional compression
class CompressedCodec<T> implements MessageCodec<T> {
  /// Constructor
  ///
  /// [compressor] the compressor to use, defaults to [NoCompression]
  const CompressedCodec(
    this._codec, {
    Compressor? compressor,
  }) : _compressor = compressor ?? NoCompression.instance;

  /// The internal codec for messages
  final MessageCodec<T> _codec;

  /// The compressor to use
  final Compressor _compressor;

  @override
  List<int>? encode(T message) {
    final data = _codec.encode(message);
    return data != null ? _compressor.compress(data) : null;
  }

  @override
  T? decode(List<int> data) {
    final decompressed = _compressor.decompress(data);
    return _codec.decode(decompressed);
  }
}
