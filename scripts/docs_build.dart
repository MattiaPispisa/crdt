import 'fs.dart';
import 'logs.dart';
import 'process.dart';

Future<void> main() async {
  logger.info('Building Docs...');
  await step(
    action: () => run('npm', ['run', 'build'], workingDir: docsDir()),
    error: 'Docs build failed',
  );
  logger.info('Docs build done ✅');
}
