import 'package:test/test.dart';

/// A matcher for a [String]
const isString = TypeMatcher<String>();

/// A matcher for an [Iterable]
TypeMatcher<Iterable<T>> isIterable<T>() => TypeMatcher<Iterable<T>>();
