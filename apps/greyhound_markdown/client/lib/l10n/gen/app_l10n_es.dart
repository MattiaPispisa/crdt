// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppL10nEs extends AppL10n {
  AppL10nEs([String locale = 'es']) : super(locale);

  @override
  String get settings => 'Ajustes';

  @override
  String get appearance => 'Apariencia';

  @override
  String get language => 'Idioma';

  @override
  String get editorSection => 'Editor';

  @override
  String get links => 'Enlaces';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get lineNumbers => 'Números de línea';

  @override
  String get lineNumbersSubtitle =>
      'Muestra los números de línea junto al código fuente';

  @override
  String get wordWrap => 'Ajuste de línea';

  @override
  String get wordWrapSubtitle =>
      'Ajusta las líneas largas en vez de desplazar la vista en horizontal';

  @override
  String get viewChangelog => 'Ver changelog';

  @override
  String get viewLicenses => 'Ver licencias';

  @override
  String get versionUnknown => '—';

  @override
  String get appTagline =>
      'Un editor de markdown colaborativo en tiempo real, creado con crdt_lf.';

  @override
  String get creditPrefix => 'Powered by crdt_lf · creado por ';

  @override
  String get linkRepo => 'GitHub';

  @override
  String get linkAppSource => 'Código de la app';

  @override
  String get linkDocs => 'Documentación de crdt_lf';

  @override
  String get yourName => 'Tu nombre';

  @override
  String get createRoom => 'Crear una sala nueva';

  @override
  String get join => 'Entrar';

  @override
  String get roomId => 'ID de la sala';

  @override
  String get recentlyOpened => 'Abiertas recientemente';

  @override
  String get relativeJustNow => 'ahora mismo';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count min',
      one: 'hace 1 min',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count h',
      one: 'hace 1 h',
    );
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'ayer';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count días',
    );
    return '$_temp0';
  }

  @override
  String roomTitle(String roomId) {
    return 'Sala $roomId';
  }

  @override
  String get copyRoomId => 'Copiar ID de la sala';

  @override
  String get roomIdCopied => 'ID de la sala copiado';

  @override
  String get viewModeEdit => 'Editar';

  @override
  String get viewModeSplit => 'Dividido';

  @override
  String get viewModeView => 'Vista';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelogLoadError => 'No se pudo cargar el changelog.';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusConnecting => 'Conectando…';

  @override
  String get statusReconnecting => 'Reconectando…';

  @override
  String get statusDisconnected => 'Desconectado';

  @override
  String get statusError => 'Error de conexión';

  @override
  String get exportDocument => 'Exportar documento';

  @override
  String exportAs(String format) {
    return 'Exportar como $format';
  }

  @override
  String get exportFileName => 'Nombre del archivo';

  @override
  String exportSaved(String fileName) {
    return '$fileName guardado';
  }

  @override
  String exportFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get shortcutUndo => 'Deshacer';

  @override
  String get shortcutRedo => 'Rehacer';

  @override
  String get shortcutBold => 'Negrita';

  @override
  String get shortcutItalic => 'Cursiva';

  @override
  String get shortcutStrikethrough => 'Tachado';

  @override
  String get shortcutInlineCode => 'Código en línea';

  @override
  String get shortcutHeading1 => 'Título 1';

  @override
  String get shortcutHeading2 => 'Título 2';

  @override
  String get shortcutHeading3 => 'Título 3';

  @override
  String get shortcutQuote => 'Cita';

  @override
  String get shortcutBulletList => 'Lista con viñetas';

  @override
  String get shortcutLink => 'Enlace';

  @override
  String get shortcutImage => 'Imagen';
}
