import 'dart:io';

import 'package:en_logger/en_logger.dart';
import 'package:image/image.dart';
import 'package:path/path.dart' as path;

/// The favicon edge, in pixels. Larger than the ~16px browsers paint, so tabs
/// stay sharp on high-density screens.
const _faviconSize = 64;

/// The edges of the PWA icons, in pixels — the sizes `manifest.json` declares.
const _iconSizes = [192, 512];

/// The share of a maskable icon guaranteed to survive the platform's crop.
/// The artwork is scaled to it and centred, so nothing important is cut.
const _maskableSafeArea = 0.8;

/// Renders the web icon set of a Flutter web app from a single square [source]
/// image: `favicon.png` plus the plain and maskable PWA icons under
/// `<webDir>/icons`.
///
/// Everything keeps [source]'s transparency, so the artwork sits on whatever
/// surface it lands on — a light or dark browser tab, a themed loading screen,
/// a launcher. The **maskable** icons are the exception: the platform crops
/// them to its own shape, so they must be opaque edge to edge and get a
/// [background] (`0xRRGGBB`) plate.
///
/// Generated rather than committed so the app icons always match the shared
/// workspace artwork.
void generateWebIcons({
  required File source,
  required Directory webDir,
  required int background,
  EnLogger? logger,
}) {
  final logo = decodePng(source.readAsBytesSync());
  if (logo == null) {
    throw FormatException('Unable to decode ${source.path}');
  }

  final iconsDir = Directory(path.join(webDir.path, 'icons'));
  if (!iconsDir.existsSync()) {
    iconsDir.createSync(recursive: true);
  }

  void write(String file, Image image) {
    File(file).writeAsBytesSync(encodePng(image));
    logger?.info('Generated ${path.basename(file)}');
  }

  write(
    path.join(webDir.path, 'favicon.png'),
    _resized(logo, _faviconSize),
  );

  for (final size in _iconSizes) {
    write(
      path.join(iconsDir.path, 'Icon-$size.png'),
      _resized(logo, size),
    );
    write(
      path.join(iconsDir.path, 'Icon-maskable-$size.png'),
      _plated(
        logo,
        size: size,
        artwork: (size * _maskableSafeArea).round(),
        background: background,
      ),
    );
  }
}

Image _resized(Image logo, int size) => copyResize(
      logo,
      width: size,
      height: size,
      interpolation: Interpolation.average,
    );

/// [logo] scaled to [artwork] pixels and centred on an opaque [size] square of
/// [background]. Opaque on purpose: a maskable icon showing through would be
/// cropped into a hole.
Image _plated(
  Image logo, {
  required int size,
  required int artwork,
  required int background,
}) {
  final scaled = _resized(logo, artwork);
  final offset = ((size - artwork) / 2).round();
  final plate = Image(width: size, height: size)
    ..clear(
      ColorRgb8(
        (background >> 16) & 0xFF,
        (background >> 8) & 0xFF,
        background & 0xFF,
      ),
    );
  return compositeImage(plate, scaled, dstX: offset, dstY: offset);
}
