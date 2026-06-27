import 'fs.dart';
import 'logs.dart';
import 'process.dart';

void main(List<String> args) async {
  final ci = args.contains('--ci');

  logger
    ..info('Bootstrapping Docs${ci ? ' (CI)' : ''}...')
    ..info('Copy assets');
  try {
    assetsDir().copySync(
      to: docsDir(subParts: ['static']),
      logger: logger,
    );
  } catch (error) {
    logger.error(
      'Unable to copy assets',
      error: error,
    );
    badExit();
  }

  logger.info('Copy package READMEs');
  try {
    copyPackageReadmes(
      to: docsDir(subParts: ['docs', 'packages']),
      logger: logger,
    );
  } catch (error) {
    logger.error(
      'Unable to copy package READMEs',
      error: error,
    );
    badExit();
  }

  logger.info('Install Docs');

  try {
    final result = await npmI(workingDir: docsDir(), ci: ci);
    if (result.isNotOk) {
      logger.error('Unable to install docs (exit code: ${result.exitCode})');
      badExit();
    }
  } catch (error) {
    logger.error(
      'Unable to install docs',
      error: error,
    );
    badExit();
  }

  logger.info('Bootstrapped Done ✅');
}
