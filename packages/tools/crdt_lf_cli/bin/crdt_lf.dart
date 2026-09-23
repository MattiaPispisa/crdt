import 'dart:io';

import 'package:crdt_lf_cli/src/command_runner.dart';

Future<void> main(List<String> args) async {
  final code = await CrdtLfCommandRunner().run(args);
  await Future.wait<void>([stdout.close(), stderr.close()]);
  exit(code);
}
