import 'dart:convert';
import 'dart:io';

class OrganizerConfig {
  OrganizerConfig({
    required this.quarantineDirectoryName,
    required this.autoOrganizedDirectoryName,
    required this.importantKeywords,
    required this.quarantineKeywords,
    required this.temporaryExtensions,
    required this.installerExtensions,
    required this.model3dExtensions,
    required this.documentExtensions,
    required this.imageExtensions,
    required this.videoAudioExtensions,
    required this.backupExtensions,
    required this.codeExtensions,
  });

  final String quarantineDirectoryName;
  final String autoOrganizedDirectoryName;
  final List<String> importantKeywords;
  final List<String> quarantineKeywords;
  final Set<String> temporaryExtensions;
  final Set<String> installerExtensions;
  final Set<String> model3dExtensions;
  final Set<String> documentExtensions;
  final Set<String> imageExtensions;
  final Set<String> videoAudioExtensions;
  final Set<String> backupExtensions;
  final Set<String> codeExtensions;

  static OrganizerConfig defaults() {
    return OrganizerConfig(
      quarantineDirectoryName: '_organiza_quarentena',
      autoOrganizedDirectoryName: '_auto_organizado',
      importantKeywords: const [
        'irpf',
        'recibo',
        'boleto',
        'fatura',
        'comprovante',
        'contracheque',
        'nota fiscal',
        'nota-fiscal',
        'nf-e',
        'cnpj',
        'cpf',
        'curriculo',
        'currículo',
        'exame',
        'resultado',
        'amil',
        'certificado',
        'dctf',
        'das',
        'imposto',
        'declaracao',
        'declaração',
        'saude',
        'saúde',
        'boletim',
        'ocorrencia',
        'ocorrência',
      ],
      quarantineKeywords: const [
        'installer',
        'instalador',
        'setup',
        'temp',
        'cache',
      ],
      temporaryExtensions: const {
        'tmp',
        'temp',
        'part',
        'crdownload',
        'download',
        'pindex.tmp',
      },
      installerExtensions: const {
        'exe',
        'msi',
        'application',
        'vbox-extpack',
      },
      model3dExtensions: const {
        '3mf',
        'stl',
        'obj',
        'skp',
      },
      documentExtensions: const {
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'csv',
        'ofx',
        'txt',
        'md',
        'eml',
      },
      imageExtensions: const {
        'png',
        'jpg',
        'jpeg',
        'gif',
        'bmp',
        'svg',
        'webp',
        'heic',
        'avif',
      },
      videoAudioExtensions: const {
        'mp4',
        'mp3',
        'm4a',
        'wav',
        'mpg',
        'mpeg',
        'mov',
        'avi',
        'mkv',
      },
      backupExtensions: const {
        'zip',
        '7z',
        'rar',
        'gz',
        'tar.gz',
        'sql.gz',
        'tar',
        'tgz',
        'sql',
        'xml',
      },
      codeExtensions: const {
        'dart',
        'php',
        'js',
        'ts',
        'html',
        'css',
        'json',
        'lua',
        'sh',
        'ipynb',
        'conf',
        'pem',
        'jks',
        'db',
      },
    );
  }

  static Future<OrganizerConfig> load(String? path) async {
    final fallback = OrganizerConfig.defaults();
    if (path == null) {
      return fallback;
    }

    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Arquivo de configuracao nao encontrado', path);
    }

    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return OrganizerConfig(
      quarantineDirectoryName:
          raw.stringValue('quarantineDirectoryName') ??
              fallback.quarantineDirectoryName,
      autoOrganizedDirectoryName:
          raw.stringValue('autoOrganizedDirectoryName') ??
              fallback.autoOrganizedDirectoryName,
      importantKeywords:
          raw.stringList('importantKeywords') ?? fallback.importantKeywords,
      quarantineKeywords:
          raw.stringList('quarantineKeywords') ?? fallback.quarantineKeywords,
      temporaryExtensions:
          raw.stringSet('temporaryExtensions') ?? fallback.temporaryExtensions,
      installerExtensions:
          raw.stringSet('installerExtensions') ?? fallback.installerExtensions,
      model3dExtensions:
          raw.stringSet('model3dExtensions') ?? fallback.model3dExtensions,
      documentExtensions:
          raw.stringSet('documentExtensions') ?? fallback.documentExtensions,
      imageExtensions: raw.stringSet('imageExtensions') ??
          fallback.imageExtensions,
      videoAudioExtensions:
          raw.stringSet('videoAudioExtensions') ??
              fallback.videoAudioExtensions,
      backupExtensions:
          raw.stringSet('backupExtensions') ?? fallback.backupExtensions,
      codeExtensions:
          raw.stringSet('codeExtensions') ?? fallback.codeExtensions,
    );
  }
}

extension _JsonMapRead on Map<String, dynamic> {
  String? stringValue(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  List<String>? stringList(String key) {
    final value = this[key];
    if (value is! List) {
      return null;
    }
    return value.whereType<String>().map((item) => item.toLowerCase()).toList();
  }

  Set<String>? stringSet(String key) => stringList(key)?.toSet();
}
