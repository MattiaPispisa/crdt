// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppL10nPt extends AppL10n {
  AppL10nPt([String locale = 'pt']) : super(locale);

  @override
  String get settings => 'Configurações';

  @override
  String get appearance => 'Aparência';

  @override
  String get language => 'Idioma';

  @override
  String get editorSection => 'Editor';

  @override
  String get links => 'Links';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get lineNumbers => 'Números de linha';

  @override
  String get lineNumbersSubtitle =>
      'Mostra os números de linha ao lado do código-fonte';

  @override
  String get wordWrap => 'Quebra de linha';

  @override
  String get wordWrapSubtitle =>
      'Quebra as linhas longas em vez de rolar na horizontal';

  @override
  String get viewChangelog => 'Ver changelog';

  @override
  String get viewLicenses => 'Ver licenças';

  @override
  String get versionUnknown => '—';

  @override
  String get appTagline =>
      'Um editor de markdown colaborativo em tempo real, feito com crdt_lf.';

  @override
  String get creditPrefix => 'Powered by crdt_lf · criado por ';

  @override
  String get linkRepo => 'GitHub';

  @override
  String get linkAppSource => 'Código do app';

  @override
  String get linkDocs => 'Documentação do crdt_lf';

  @override
  String get yourName => 'Seu nome';

  @override
  String get createRoom => 'Criar uma sala nova';

  @override
  String get join => 'Entrar';

  @override
  String get roomId => 'ID da sala';

  @override
  String get recentlyOpened => 'Abertas recentemente';

  @override
  String get relativeJustNow => 'agora mesmo';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count min',
      one: 'há 1 min',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count h',
      one: 'há 1 h',
    );
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'ontem';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count dias',
    );
    return '$_temp0';
  }

  @override
  String roomTitle(String roomId) {
    return 'Sala $roomId';
  }

  @override
  String get copyRoomId => 'Copiar ID da sala';

  @override
  String get roomIdCopied => 'ID da sala copiado';

  @override
  String get viewModeEdit => 'Editar';

  @override
  String get viewModeSplit => 'Dividido';

  @override
  String get viewModeView => 'Visualizar';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelogLoadError => 'Não foi possível carregar o changelog.';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusConnecting => 'Conectando…';

  @override
  String get statusReconnecting => 'Reconectando…';

  @override
  String get statusDisconnected => 'Desconectado';

  @override
  String get statusError => 'Erro de conexão';

  @override
  String get exportDocument => 'Exportar documento';

  @override
  String exportAs(String format) {
    return 'Exportar como $format';
  }

  @override
  String get exportFileName => 'Nome do arquivo';

  @override
  String exportSaved(String fileName) {
    return '$fileName salvo';
  }

  @override
  String exportFailed(String error) {
    return 'Falha ao exportar: $error';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Salvar';

  @override
  String get shortcutUndo => 'Desfazer';

  @override
  String get shortcutRedo => 'Refazer';

  @override
  String get shortcutBold => 'Negrito';

  @override
  String get shortcutItalic => 'Itálico';

  @override
  String get shortcutStrikethrough => 'Tachado';

  @override
  String get shortcutInlineCode => 'Código inline';

  @override
  String get shortcutHeading1 => 'Título 1';

  @override
  String get shortcutHeading2 => 'Título 2';

  @override
  String get shortcutHeading3 => 'Título 3';

  @override
  String get shortcutQuote => 'Citação';

  @override
  String get shortcutBulletList => 'Lista com marcadores';

  @override
  String get shortcutLink => 'Link';

  @override
  String get shortcutImage => 'Imagem';
}
