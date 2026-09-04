// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ChangesTable extends Changes with TableInfo<$ChangesTable, ChangeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta =
      const VerificationMeta('documentId');
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
      'document_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _changeIdMeta =
      const VerificationMeta('changeId');
  @override
  late final GeneratedColumn<String> changeId = GeneratedColumn<String>(
      'change_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
      'bytes', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [documentId, changeId, bytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'changes';
  @override
  VerificationContext validateIntegrity(Insertable<ChangeRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
          _documentIdMeta,
          documentId.isAcceptableOrUnknown(
              data['document_id']!, _documentIdMeta));
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('change_id')) {
      context.handle(_changeIdMeta,
          changeId.isAcceptableOrUnknown(data['change_id']!, _changeIdMeta));
    } else if (isInserting) {
      context.missing(_changeIdMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
          _bytesMeta, bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta));
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId, changeId};
  @override
  ChangeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChangeRow(
      documentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}document_id'])!,
      changeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}change_id'])!,
      bytes: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}bytes'])!,
    );
  }

  @override
  $ChangesTable createAlias(String alias) {
    return $ChangesTable(attachedDatabase, alias);
  }
}

class ChangeRow extends DataClass implements Insertable<ChangeRow> {
  /// Identifier of the document the change belongs to.
  final String documentId;

  /// Identifier of the change (`change.id.toString()`).
  final String changeId;

  /// The serialized change (`Change.toBytes()`).
  final Uint8List bytes;
  const ChangeRow(
      {required this.documentId, required this.changeId, required this.bytes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['change_id'] = Variable<String>(changeId);
    map['bytes'] = Variable<Uint8List>(bytes);
    return map;
  }

  ChangesCompanion toCompanion(bool nullToAbsent) {
    return ChangesCompanion(
      documentId: Value(documentId),
      changeId: Value(changeId),
      bytes: Value(bytes),
    );
  }

  factory ChangeRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChangeRow(
      documentId: serializer.fromJson<String>(json['documentId']),
      changeId: serializer.fromJson<String>(json['changeId']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'changeId': serializer.toJson<String>(changeId),
      'bytes': serializer.toJson<Uint8List>(bytes),
    };
  }

  ChangeRow copyWith(
          {String? documentId, String? changeId, Uint8List? bytes}) =>
      ChangeRow(
        documentId: documentId ?? this.documentId,
        changeId: changeId ?? this.changeId,
        bytes: bytes ?? this.bytes,
      );
  ChangeRow copyWithCompanion(ChangesCompanion data) {
    return ChangeRow(
      documentId:
          data.documentId.present ? data.documentId.value : this.documentId,
      changeId: data.changeId.present ? data.changeId.value : this.changeId,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChangeRow(')
          ..write('documentId: $documentId, ')
          ..write('changeId: $changeId, ')
          ..write('bytes: $bytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(documentId, changeId, $driftBlobEquality.hash(bytes));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChangeRow &&
          other.documentId == this.documentId &&
          other.changeId == this.changeId &&
          $driftBlobEquality.equals(other.bytes, this.bytes));
}

class ChangesCompanion extends UpdateCompanion<ChangeRow> {
  final Value<String> documentId;
  final Value<String> changeId;
  final Value<Uint8List> bytes;
  final Value<int> rowid;
  const ChangesCompanion({
    this.documentId = const Value.absent(),
    this.changeId = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChangesCompanion.insert({
    required String documentId,
    required String changeId,
    required Uint8List bytes,
    this.rowid = const Value.absent(),
  })  : documentId = Value(documentId),
        changeId = Value(changeId),
        bytes = Value(bytes);
  static Insertable<ChangeRow> custom({
    Expression<String>? documentId,
    Expression<String>? changeId,
    Expression<Uint8List>? bytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (changeId != null) 'change_id': changeId,
      if (bytes != null) 'bytes': bytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChangesCompanion copyWith(
      {Value<String>? documentId,
      Value<String>? changeId,
      Value<Uint8List>? bytes,
      Value<int>? rowid}) {
    return ChangesCompanion(
      documentId: documentId ?? this.documentId,
      changeId: changeId ?? this.changeId,
      bytes: bytes ?? this.bytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (changeId.present) {
      map['change_id'] = Variable<String>(changeId.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChangesCompanion(')
          ..write('documentId: $documentId, ')
          ..write('changeId: $changeId, ')
          ..write('bytes: $bytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnapshotsTable extends Snapshots
    with TableInfo<$SnapshotsTable, SnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta =
      const VerificationMeta('documentId');
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
      'document_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _snapshotIdMeta =
      const VerificationMeta('snapshotId');
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
      'snapshot_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
      'bytes', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [documentId, snapshotId, bytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshots';
  @override
  VerificationContext validateIntegrity(Insertable<SnapshotRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
          _documentIdMeta,
          documentId.isAcceptableOrUnknown(
              data['document_id']!, _documentIdMeta));
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
          _snapshotIdMeta,
          snapshotId.isAcceptableOrUnknown(
              data['snapshot_id']!, _snapshotIdMeta));
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
          _bytesMeta, bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta));
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId, snapshotId};
  @override
  SnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotRow(
      documentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}document_id'])!,
      snapshotId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}snapshot_id'])!,
      bytes: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}bytes'])!,
    );
  }

  @override
  $SnapshotsTable createAlias(String alias) {
    return $SnapshotsTable(attachedDatabase, alias);
  }
}

class SnapshotRow extends DataClass implements Insertable<SnapshotRow> {
  /// Identifier of the document the snapshot belongs to.
  final String documentId;

  /// Identifier of the snapshot (`snapshot.id`).
  final String snapshotId;

  /// The serialized snapshot (`Snapshot.toBytes()`).
  final Uint8List bytes;
  const SnapshotRow(
      {required this.documentId,
      required this.snapshotId,
      required this.bytes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['bytes'] = Variable<Uint8List>(bytes);
    return map;
  }

  SnapshotsCompanion toCompanion(bool nullToAbsent) {
    return SnapshotsCompanion(
      documentId: Value(documentId),
      snapshotId: Value(snapshotId),
      bytes: Value(bytes),
    );
  }

  factory SnapshotRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotRow(
      documentId: serializer.fromJson<String>(json['documentId']),
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'snapshotId': serializer.toJson<String>(snapshotId),
      'bytes': serializer.toJson<Uint8List>(bytes),
    };
  }

  SnapshotRow copyWith(
          {String? documentId, String? snapshotId, Uint8List? bytes}) =>
      SnapshotRow(
        documentId: documentId ?? this.documentId,
        snapshotId: snapshotId ?? this.snapshotId,
        bytes: bytes ?? this.bytes,
      );
  SnapshotRow copyWithCompanion(SnapshotsCompanion data) {
    return SnapshotRow(
      documentId:
          data.documentId.present ? data.documentId.value : this.documentId,
      snapshotId:
          data.snapshotId.present ? data.snapshotId.value : this.snapshotId,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotRow(')
          ..write('documentId: $documentId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('bytes: $bytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(documentId, snapshotId, $driftBlobEquality.hash(bytes));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotRow &&
          other.documentId == this.documentId &&
          other.snapshotId == this.snapshotId &&
          $driftBlobEquality.equals(other.bytes, this.bytes));
}

class SnapshotsCompanion extends UpdateCompanion<SnapshotRow> {
  final Value<String> documentId;
  final Value<String> snapshotId;
  final Value<Uint8List> bytes;
  final Value<int> rowid;
  const SnapshotsCompanion({
    this.documentId = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotsCompanion.insert({
    required String documentId,
    required String snapshotId,
    required Uint8List bytes,
    this.rowid = const Value.absent(),
  })  : documentId = Value(documentId),
        snapshotId = Value(snapshotId),
        bytes = Value(bytes);
  static Insertable<SnapshotRow> custom({
    Expression<String>? documentId,
    Expression<String>? snapshotId,
    Expression<Uint8List>? bytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (bytes != null) 'bytes': bytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotsCompanion copyWith(
      {Value<String>? documentId,
      Value<String>? snapshotId,
      Value<Uint8List>? bytes,
      Value<int>? rowid}) {
    return SnapshotsCompanion(
      documentId: documentId ?? this.documentId,
      snapshotId: snapshotId ?? this.snapshotId,
      bytes: bytes ?? this.bytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('bytes: $bytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeersTable extends Peers with TableInfo<$PeersTable, PeerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta =
      const VerificationMeta('documentId');
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
      'document_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
      'peer_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [documentId, peerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peers';
  @override
  VerificationContext validateIntegrity(Insertable<PeerRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
          _documentIdMeta,
          documentId.isAcceptableOrUnknown(
              data['document_id']!, _documentIdMeta));
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(_peerIdMeta,
          peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta));
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  PeerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeerRow(
      documentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}document_id'])!,
      peerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}peer_id'])!,
    );
  }

  @override
  $PeersTable createAlias(String alias) {
    return $PeersTable(attachedDatabase, alias);
  }
}

class PeerRow extends DataClass implements Insertable<PeerRow> {
  /// Identifier of the document the identity belongs to.
  final String documentId;

  /// The peer id as text (`PeerId.toString()`).
  final String peerId;
  const PeerRow({required this.documentId, required this.peerId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['peer_id'] = Variable<String>(peerId);
    return map;
  }

  PeersCompanion toCompanion(bool nullToAbsent) {
    return PeersCompanion(
      documentId: Value(documentId),
      peerId: Value(peerId),
    );
  }

  factory PeerRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeerRow(
      documentId: serializer.fromJson<String>(json['documentId']),
      peerId: serializer.fromJson<String>(json['peerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'peerId': serializer.toJson<String>(peerId),
    };
  }

  PeerRow copyWith({String? documentId, String? peerId}) => PeerRow(
        documentId: documentId ?? this.documentId,
        peerId: peerId ?? this.peerId,
      );
  PeerRow copyWithCompanion(PeersCompanion data) {
    return PeerRow(
      documentId:
          data.documentId.present ? data.documentId.value : this.documentId,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeerRow(')
          ..write('documentId: $documentId, ')
          ..write('peerId: $peerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(documentId, peerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerRow &&
          other.documentId == this.documentId &&
          other.peerId == this.peerId);
}

class PeersCompanion extends UpdateCompanion<PeerRow> {
  final Value<String> documentId;
  final Value<String> peerId;
  final Value<int> rowid;
  const PeersCompanion({
    this.documentId = const Value.absent(),
    this.peerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeersCompanion.insert({
    required String documentId,
    required String peerId,
    this.rowid = const Value.absent(),
  })  : documentId = Value(documentId),
        peerId = Value(peerId);
  static Insertable<PeerRow> custom({
    Expression<String>? documentId,
    Expression<String>? peerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (peerId != null) 'peer_id': peerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeersCompanion copyWith(
      {Value<String>? documentId, Value<String>? peerId, Value<int>? rowid}) {
    return PeersCompanion(
      documentId: documentId ?? this.documentId,
      peerId: peerId ?? this.peerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeersCompanion(')
          ..write('documentId: $documentId, ')
          ..write('peerId: $peerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CRDTDriftDatabase extends GeneratedDatabase {
  _$CRDTDriftDatabase(QueryExecutor e) : super(e);
  $CRDTDriftDatabaseManager get managers => $CRDTDriftDatabaseManager(this);
  late final $ChangesTable changes = $ChangesTable(this);
  late final $SnapshotsTable snapshots = $SnapshotsTable(this);
  late final $PeersTable peers = $PeersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [changes, snapshots, peers];
}

typedef $$ChangesTableCreateCompanionBuilder = ChangesCompanion Function({
  required String documentId,
  required String changeId,
  required Uint8List bytes,
  Value<int> rowid,
});
typedef $$ChangesTableUpdateCompanionBuilder = ChangesCompanion Function({
  Value<String> documentId,
  Value<String> changeId,
  Value<Uint8List> bytes,
  Value<int> rowid,
});

class $$ChangesTableFilterComposer
    extends Composer<_$CRDTDriftDatabase, $ChangesTable> {
  $$ChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get changeId => $composableBuilder(
      column: $table.changeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnFilters(column));
}

class $$ChangesTableOrderingComposer
    extends Composer<_$CRDTDriftDatabase, $ChangesTable> {
  $$ChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get changeId => $composableBuilder(
      column: $table.changeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnOrderings(column));
}

class $$ChangesTableAnnotationComposer
    extends Composer<_$CRDTDriftDatabase, $ChangesTable> {
  $$ChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => column);

  GeneratedColumn<String> get changeId =>
      $composableBuilder(column: $table.changeId, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);
}

class $$ChangesTableTableManager extends RootTableManager<
    _$CRDTDriftDatabase,
    $ChangesTable,
    ChangeRow,
    $$ChangesTableFilterComposer,
    $$ChangesTableOrderingComposer,
    $$ChangesTableAnnotationComposer,
    $$ChangesTableCreateCompanionBuilder,
    $$ChangesTableUpdateCompanionBuilder,
    (ChangeRow, BaseReferences<_$CRDTDriftDatabase, $ChangesTable, ChangeRow>),
    ChangeRow,
    PrefetchHooks Function()> {
  $$ChangesTableTableManager(_$CRDTDriftDatabase db, $ChangesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> documentId = const Value.absent(),
            Value<String> changeId = const Value.absent(),
            Value<Uint8List> bytes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChangesCompanion(
            documentId: documentId,
            changeId: changeId,
            bytes: bytes,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String documentId,
            required String changeId,
            required Uint8List bytes,
            Value<int> rowid = const Value.absent(),
          }) =>
              ChangesCompanion.insert(
            documentId: documentId,
            changeId: changeId,
            bytes: bytes,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChangesTableProcessedTableManager = ProcessedTableManager<
    _$CRDTDriftDatabase,
    $ChangesTable,
    ChangeRow,
    $$ChangesTableFilterComposer,
    $$ChangesTableOrderingComposer,
    $$ChangesTableAnnotationComposer,
    $$ChangesTableCreateCompanionBuilder,
    $$ChangesTableUpdateCompanionBuilder,
    (ChangeRow, BaseReferences<_$CRDTDriftDatabase, $ChangesTable, ChangeRow>),
    ChangeRow,
    PrefetchHooks Function()>;
typedef $$SnapshotsTableCreateCompanionBuilder = SnapshotsCompanion Function({
  required String documentId,
  required String snapshotId,
  required Uint8List bytes,
  Value<int> rowid,
});
typedef $$SnapshotsTableUpdateCompanionBuilder = SnapshotsCompanion Function({
  Value<String> documentId,
  Value<String> snapshotId,
  Value<Uint8List> bytes,
  Value<int> rowid,
});

class $$SnapshotsTableFilterComposer
    extends Composer<_$CRDTDriftDatabase, $SnapshotsTable> {
  $$SnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get snapshotId => $composableBuilder(
      column: $table.snapshotId, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnFilters(column));
}

class $$SnapshotsTableOrderingComposer
    extends Composer<_$CRDTDriftDatabase, $SnapshotsTable> {
  $$SnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get snapshotId => $composableBuilder(
      column: $table.snapshotId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnOrderings(column));
}

class $$SnapshotsTableAnnotationComposer
    extends Composer<_$CRDTDriftDatabase, $SnapshotsTable> {
  $$SnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => column);

  GeneratedColumn<String> get snapshotId => $composableBuilder(
      column: $table.snapshotId, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);
}

class $$SnapshotsTableTableManager extends RootTableManager<
    _$CRDTDriftDatabase,
    $SnapshotsTable,
    SnapshotRow,
    $$SnapshotsTableFilterComposer,
    $$SnapshotsTableOrderingComposer,
    $$SnapshotsTableAnnotationComposer,
    $$SnapshotsTableCreateCompanionBuilder,
    $$SnapshotsTableUpdateCompanionBuilder,
    (
      SnapshotRow,
      BaseReferences<_$CRDTDriftDatabase, $SnapshotsTable, SnapshotRow>
    ),
    SnapshotRow,
    PrefetchHooks Function()> {
  $$SnapshotsTableTableManager(_$CRDTDriftDatabase db, $SnapshotsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> documentId = const Value.absent(),
            Value<String> snapshotId = const Value.absent(),
            Value<Uint8List> bytes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SnapshotsCompanion(
            documentId: documentId,
            snapshotId: snapshotId,
            bytes: bytes,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String documentId,
            required String snapshotId,
            required Uint8List bytes,
            Value<int> rowid = const Value.absent(),
          }) =>
              SnapshotsCompanion.insert(
            documentId: documentId,
            snapshotId: snapshotId,
            bytes: bytes,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SnapshotsTableProcessedTableManager = ProcessedTableManager<
    _$CRDTDriftDatabase,
    $SnapshotsTable,
    SnapshotRow,
    $$SnapshotsTableFilterComposer,
    $$SnapshotsTableOrderingComposer,
    $$SnapshotsTableAnnotationComposer,
    $$SnapshotsTableCreateCompanionBuilder,
    $$SnapshotsTableUpdateCompanionBuilder,
    (
      SnapshotRow,
      BaseReferences<_$CRDTDriftDatabase, $SnapshotsTable, SnapshotRow>
    ),
    SnapshotRow,
    PrefetchHooks Function()>;
typedef $$PeersTableCreateCompanionBuilder = PeersCompanion Function({
  required String documentId,
  required String peerId,
  Value<int> rowid,
});
typedef $$PeersTableUpdateCompanionBuilder = PeersCompanion Function({
  Value<String> documentId,
  Value<String> peerId,
  Value<int> rowid,
});

class $$PeersTableFilterComposer
    extends Composer<_$CRDTDriftDatabase, $PeersTable> {
  $$PeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get peerId => $composableBuilder(
      column: $table.peerId, builder: (column) => ColumnFilters(column));
}

class $$PeersTableOrderingComposer
    extends Composer<_$CRDTDriftDatabase, $PeersTable> {
  $$PeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get peerId => $composableBuilder(
      column: $table.peerId, builder: (column) => ColumnOrderings(column));
}

class $$PeersTableAnnotationComposer
    extends Composer<_$CRDTDriftDatabase, $PeersTable> {
  $$PeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
      column: $table.documentId, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);
}

class $$PeersTableTableManager extends RootTableManager<
    _$CRDTDriftDatabase,
    $PeersTable,
    PeerRow,
    $$PeersTableFilterComposer,
    $$PeersTableOrderingComposer,
    $$PeersTableAnnotationComposer,
    $$PeersTableCreateCompanionBuilder,
    $$PeersTableUpdateCompanionBuilder,
    (PeerRow, BaseReferences<_$CRDTDriftDatabase, $PeersTable, PeerRow>),
    PeerRow,
    PrefetchHooks Function()> {
  $$PeersTableTableManager(_$CRDTDriftDatabase db, $PeersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> documentId = const Value.absent(),
            Value<String> peerId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PeersCompanion(
            documentId: documentId,
            peerId: peerId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String documentId,
            required String peerId,
            Value<int> rowid = const Value.absent(),
          }) =>
              PeersCompanion.insert(
            documentId: documentId,
            peerId: peerId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PeersTableProcessedTableManager = ProcessedTableManager<
    _$CRDTDriftDatabase,
    $PeersTable,
    PeerRow,
    $$PeersTableFilterComposer,
    $$PeersTableOrderingComposer,
    $$PeersTableAnnotationComposer,
    $$PeersTableCreateCompanionBuilder,
    $$PeersTableUpdateCompanionBuilder,
    (PeerRow, BaseReferences<_$CRDTDriftDatabase, $PeersTable, PeerRow>),
    PeerRow,
    PrefetchHooks Function()>;

class $CRDTDriftDatabaseManager {
  final _$CRDTDriftDatabase _db;
  $CRDTDriftDatabaseManager(this._db);
  $$ChangesTableTableManager get changes =>
      $$ChangesTableTableManager(_db, _db.changes);
  $$SnapshotsTableTableManager get snapshots =>
      $$SnapshotsTableTableManager(_db, _db.snapshots);
  $$PeersTableTableManager get peers =>
      $$PeersTableTableManager(_db, _db.peers);
}
