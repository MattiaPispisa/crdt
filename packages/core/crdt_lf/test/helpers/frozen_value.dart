import 'package:test/test.dart';

/// Checks the value contract of a collection handler: the value [read]
/// returns cannot be edited, and stays the same object until [write] changes
/// the handler.
///
/// [edit] tries to change the value it is given, the way a caller would.
/// [fixed] checks that a value read before [write] still reads as it did.
void expectFrozenValue<V extends Object>({
  required V Function() read,
  required void Function(V value) edit,
  required void Function() write,
  bool fixed = true,
}) {
  final before = read();
  final text = before.toString();

  expect(() => edit(before), throwsUnsupportedError);
  expect(identical(read(), before), isTrue);

  write();

  expect(before.toString() == text, fixed);
  expect(identical(read(), before), isFalse);
}
