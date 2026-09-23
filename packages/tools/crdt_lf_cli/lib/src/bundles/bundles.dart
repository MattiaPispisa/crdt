// GENERATED CODE - DO NOT MODIFY BY HAND
// Run `dart run tool/generate_bundles.dart` instead.
// ignore_for_file: type=lint

import 'package:mason/mason.dart';

import 'handler_fugue_text_bundle.dart';
import 'handler_none_bundle.dart';
import 'server_plain_bundle.dart';
import 'shared_bundle.dart';
import 'storage_drift_bundle.dart';
import 'storage_hive_bundle.dart';
import 'storage_infrastructure_bundle.dart';
import 'storage_sqlite_bundle.dart';
import 'workspace_bundle.dart';

/// Every brick of the CLI, by name.
final bundles = <String, MasonBundle>{
  'handler_fugue_text': handlerFugueTextBundle,
  'handler_none': handlerNoneBundle,
  'server_plain': serverPlainBundle,
  'shared': sharedBundle,
  'storage_drift': storageDriftBundle,
  'storage_hive': storageHiveBundle,
  'storage_infrastructure': storageInfrastructureBundle,
  'storage_sqlite': storageSqliteBundle,
  'workspace': workspaceBundle,
};
