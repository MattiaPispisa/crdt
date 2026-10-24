// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// A note of an [Asset], addressed by the id of the event that created it.
class Note {
  /// Creates a note.
  const Note(this.id, this.text);

  /// The id of the event that created the note.
  final EventId id;

  /// What the note says.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Note && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'Note($text)';
}

/// The aggregate the tests build: a name, notes and measures.
class Asset {
  /// Creates an asset.
  const Asset({
    this.displayName = '',
    this.notes = const [],
    this.measures = const [],
  });

  /// The name shown to the user.
  final String displayName;

  /// The notes, in order.
  final List<Note> notes;

  /// The measures, in order.
  final List<String> measures;

  /// The texts of [notes], in order.
  List<String> get noteTexts => [for (final note in notes) note.text];

  /// What this asset holds, without the note ids: two peers that wrote the
  /// same edits agree on it even though their ids differ.
  String get content => '$displayName|${noteTexts.join(',')}|'
      '${measures.join(',')}';

  /// A copy with the given fields replaced.
  Asset copyWith({
    String? displayName,
    List<Note>? notes,
    List<String>? measures,
  }) =>
      Asset(
        displayName: displayName ?? this.displayName,
        notes: notes ?? this.notes,
        measures: measures ?? this.measures,
      );

  /// Where the note [id] is, or `-1`.
  int indexOfNote(EventId id) => notes.indexWhere((note) => note.id == id);

  @override
  bool operator ==(Object other) =>
      other is Asset &&
      other.displayName == displayName &&
      _listEquals(other.notes, notes) &&
      _listEquals(other.measures, measures);

  @override
  int get hashCode => Object.hash(
        displayName,
        Object.hashAll(notes),
        Object.hashAll(measures),
      );

  @override
  String toString() => 'Asset($displayName, $noteTexts, $measures)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// What happens to an [Asset].
sealed class AssetEvent {
  const AssetEvent();
}

/// Sets the name.
final class Renamed extends AssetEvent {
  /// Creates the event.
  const Renamed(this.name);

  /// The new name.
  final String name;

  @override
  bool operator ==(Object other) => other is Renamed && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Adds a note after [after], or first when [after] is `null`.
final class NoteAdded extends AssetEvent {
  /// Creates the event.
  const NoteAdded(this.text, {this.after});

  /// What the note says.
  final String text;

  /// The note it goes after.
  final EventId? after;

  @override
  bool operator ==(Object other) =>
      other is NoteAdded && other.text == text && other.after == after;

  @override
  int get hashCode => Object.hash(text, after);
}

/// Puts back the note [note] with its own id.
final class NoteRestored extends AssetEvent {
  /// Creates the event.
  const NoteRestored(this.note, this.text, {this.after});

  /// The id of the note.
  final EventId note;

  /// What the note says.
  final String text;

  /// The note it goes after.
  final EventId? after;

  @override
  bool operator ==(Object other) =>
      other is NoteRestored &&
      other.note == note &&
      other.text == text &&
      other.after == after;

  @override
  int get hashCode => Object.hash(note, text, after);
}

/// Replaces the text of the note [note].
final class NoteUpdated extends AssetEvent {
  /// Creates the event.
  const NoteUpdated(this.note, this.text);

  /// The id of the note.
  final EventId note;

  /// The new text.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is NoteUpdated && other.note == note && other.text == text;

  @override
  int get hashCode => Object.hash(note, text);
}

/// Removes the note [note].
final class NoteRemoved extends AssetEvent {
  /// Creates the event.
  const NoteRemoved(this.note);

  /// The id of the note.
  final EventId note;

  @override
  bool operator ==(Object other) => other is NoteRemoved && other.note == note;

  @override
  int get hashCode => note.hashCode;
}

/// Appends a measure.
final class MeasureAdded extends AssetEvent {
  /// Creates the event.
  const MeasureAdded(this.value);

  /// The measure.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MeasureAdded && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The [Asset] aggregate, undoable.
final class AssetAggregate
    extends InvertibleAggregateDefinition<Asset, AssetEvent> {
  /// Creates the definition.
  const AssetAggregate();

  @override
  String get handlerType => 'test.asset';

  @override
  Asset initial(String id) => const Asset();

  @override
  Asset reduce(Asset state, AssetEvent event, EventContext context) {
    switch (event) {
      case Renamed(:final name):
        return state.copyWith(displayName: name);
      case NoteAdded(:final text, :final after):
        return _insert(state, Note(context.id, text), after);
      case NoteRestored(:final note, :final text, :final after):
        if (state.indexOfNote(note) != -1) {
          return state;
        }
        return _insert(state, Note(note, text), after);
      case NoteUpdated(:final note, :final text):
        final index = state.indexOfNote(note);
        if (index == -1) {
          return state;
        }
        return state.copyWith(
          notes: [...state.notes]..[index] = Note(note, text),
        );
      case NoteRemoved(:final note):
        final index = state.indexOfNote(note);
        if (index == -1) {
          return state;
        }
        return state.copyWith(notes: [...state.notes]..removeAt(index));
      case MeasureAdded(:final value):
        return state.copyWith(measures: [...state.measures, value]);
    }
  }

  static Asset _insert(Asset state, Note note, EventId? after) {
    final anchor = after == null ? -1 : state.indexOfNote(after);
    return state.copyWith(notes: [...state.notes]..insert(anchor + 1, note));
  }

  @override
  List<AssetEvent> invert(
    Asset before,
    AssetEvent event,
    EventContext context,
  ) {
    switch (event) {
      case Renamed():
        return [Renamed(before.displayName)];
      case NoteAdded():
        return [NoteRemoved(context.id)];
      case NoteRestored(:final note):
        return before.indexOfNote(note) == -1 ? [NoteRemoved(note)] : const [];
      case NoteUpdated(:final note):
        final index = before.indexOfNote(note);
        return index == -1
            ? const []
            : [NoteUpdated(note, before.notes[index].text)];
      case NoteRemoved(:final note):
        final index = before.indexOfNote(note);
        if (index == -1) {
          return const [];
        }
        return [
          NoteRestored(
            note,
            before.notes[index].text,
            after: index == 0 ? null : before.notes[index - 1].id,
          ),
        ];
      case MeasureAdded():
        return const [];
    }
  }

  @override
  ValueCodec<AssetEvent> get eventCodec => const AssetEventCodec();

  @override
  ValueCodec<Asset> get stateCodec => const AssetCodec();
}

/// Binary codec of [AssetEvent].
class AssetEventCodec implements ValueCodec<AssetEvent> {
  /// Creates the codec.
  const AssetEventCodec();

  @override
  Uint8List encode(AssetEvent value) {
    final out = BytesBuilder(copy: false);
    switch (value) {
      case Renamed(:final name):
        out.addByte(0);
        UVarint.writeString(name, out);
      case NoteAdded(:final text, :final after):
        out.addByte(1);
        UVarint.writeString(text, out);
        _writeOptionalId(after, out);
      case NoteRestored(:final note, :final text, :final after):
        out.addByte(2);
        note.writeTo(out);
        UVarint.writeString(text, out);
        _writeOptionalId(after, out);
      case NoteUpdated(:final note, :final text):
        out.addByte(3);
        note.writeTo(out);
        UVarint.writeString(text, out);
      case NoteRemoved(:final note):
        out.addByte(4);
        note.writeTo(out);
      case MeasureAdded(:final value):
        out.addByte(5);
        UVarint.writeString(value, out);
    }
    return out.toBytes();
  }

  @override
  AssetEvent decode(Uint8List bytes) {
    final reader = _Reader(bytes, 1);
    switch (bytes[0]) {
      case 0:
        return Renamed(reader.string());
      case 1:
        return NoteAdded(reader.string(), after: reader.optionalId());
      case 2:
        return NoteRestored(
          reader.id(),
          reader.string(),
          after: reader.optionalId(),
        );
      case 3:
        return NoteUpdated(reader.id(), reader.string());
      case 4:
        return NoteRemoved(reader.id());
      case 5:
        return MeasureAdded(reader.string());
      default:
        throw FormatException('Unknown asset event ${bytes[0]}');
    }
  }
}

/// Binary codec of [Asset].
class AssetCodec implements ValueCodec<Asset> {
  /// Creates the codec.
  const AssetCodec();

  @override
  Uint8List encode(Asset value) {
    final out = BytesBuilder(copy: false);
    UVarint.writeString(value.displayName, out);
    UVarint.write(value.notes.length, out);
    for (final note in value.notes) {
      note.id.writeTo(out);
      UVarint.writeString(note.text, out);
    }
    UVarint.write(value.measures.length, out);
    for (final measure in value.measures) {
      UVarint.writeString(measure, out);
    }
    return out.toBytes();
  }

  @override
  Asset decode(Uint8List bytes) {
    final reader = _Reader(bytes, 0);
    final displayName = reader.string();
    final notes = [
      for (var i = reader.count(); i > 0; i--)
        Note(reader.id(), reader.string()),
    ];
    final measures = [for (var i = reader.count(); i > 0; i--) reader.string()];
    return Asset(displayName: displayName, notes: notes, measures: measures);
  }
}

void _writeOptionalId(EventId? id, BytesBuilder out) {
  if (id == null) {
    out.addByte(0);
    return;
  }
  out.addByte(1);
  id.writeTo(out);
}

class _Reader {
  _Reader(this._bytes, this._offset);

  final Uint8List _bytes;
  int _offset;

  String string() {
    final record = UVarint.readString(_bytes, offset: _offset, what: 'string');
    _offset = record.nextOffset;
    return record.value;
  }

  int count() {
    final record = UVarint.read(_bytes, offset: _offset);
    _offset = record.nextOffset;
    return record.value;
  }

  EventId id() {
    final record = EventId.readFromBytes(_bytes, offset: _offset);
    _offset = record.nextOffset;
    return record.value;
  }

  EventId? optionalId() {
    final present = _bytes[_offset++];
    return present == 0 ? null : id();
  }
}

/// Writes one random event to [asset], named after [token].
///
/// Every event it writes changes the value and has an inverse, as the
/// conformance suite asks.
void randomAssetEdit(
  CRDTAggregateHandler<Asset, AssetEvent> asset,
  Random random,
  String token,
) {
  final notes = asset.value.notes;
  EventId pick() => notes[random.nextInt(notes.length)].id;
  switch (notes.isEmpty ? random.nextInt(2) : random.nextInt(4)) {
    case 0:
      asset.dispatch(Renamed('name $token'));
    case 1:
      asset.dispatch(
        NoteAdded('note $token', after: notes.isEmpty ? null : pick()),
      );
    case 2:
      asset.dispatch(NoteUpdated(pick(), 'edit $token'));
    default:
      asset.dispatch(NoteRemoved(pick()));
  }
}
