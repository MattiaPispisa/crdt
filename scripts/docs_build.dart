import 'fs.dart';
import 'logs.dart';
import 'process.dart';

void main() async {
  logger.info('Building Docs...');

  final result = await npmRunBuild(workingDir: docsDir());
  if (result.isNotOk) {
    logger.error('Docs build failed (exit code: ${result.exitCode})');
    badExit();
  }

  logger.info('Docs build done ✅');
}
