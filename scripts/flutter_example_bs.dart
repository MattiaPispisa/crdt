import 'fs.dart';
import 'logs.dart';
import 'process.dart';

/// Copies the shared workspace assets into the Flutter example so it can
/// reference them as bundled assets (see its `pubspec.yaml`).
///
/// Run as the `melos bootstrap` post hook, mirroring what `docs_bs` does for
/// the documentation site.
void main() {
  logger
    ..info('Bootstrapping flutter_example...')
    ..info('Copy assets');
  try {
    assetsDir().copySync(
      to: flutterExampleDir(subParts: ['assets']),
      logger: logger,
    );
  } catch (error) {
    logger.error(
      'Unable to copy assets',
      error: error,
    );
    badExit();
  }

  logger.info('flutter_example assets ready ✅');
}
