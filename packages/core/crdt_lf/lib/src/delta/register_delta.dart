import 'package:crdt_lf/src/delta/handler_update.dart';

/// How a register handler's value moved.
final class RegisterDelta<T> implements ComposableDelta<RegisterDelta<T>> {
  /// The register went from [previous] to [current].
  const RegisterDelta({required this.previous, required this.current});

  /// What the register held before, or `null` when it held nothing.
  final T? previous;

  /// What the register holds now, or `null` when it holds nothing.
  final T? current;

  @override
  bool get isEmpty => previous == current;

  /// Whether this delta moves something.
  bool get isNotEmpty => !isEmpty;

  /// The delta that has the same effect as this one followed by [next].
  ///
  /// Only the two ends matter: a register keeps one value.
  @override
  RegisterDelta<T> compose(RegisterDelta<T> next) =>
      RegisterDelta<T>(previous: previous, current: next.current);

  /// What the register holds once this delta is applied, which is [current].
  ///
  /// [base] is ignored: a register keeps one value, and the delta already
  /// carries it. The parameter is there so every delta type applies the same
  /// way.
  T? apply(T? base) => current;

  @override
  bool operator ==(Object other) =>
      other is RegisterDelta<T> &&
      other.previous == previous &&
      other.current == current;

  @override
  int get hashCode => Object.hash(RegisterDelta<T>, previous, current);

  @override
  String toString() => 'RegisterDelta($previous -> $current)';
}
