import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:organiza_downloads/src/ai_categories.dart';
import 'package:organiza_downloads/src/ai_classifier.dart';
import 'package:organiza_downloads/src/analyzer.dart';
import 'package:organiza_downloads/src/cleanup.dart';
import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/csv_report.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:organiza_downloads/src/progress.dart';
import 'package:organiza_downloads/src/quarantine.dart';
import 'package:organiza_downloads/src/reevaluate.dart';
import 'package:organiza_downloads/src/run_logger.dart';

enum RunMode {
  cold,
  real,
}

const _defaultCsvFileName = 'organiza_downloads_relatorio.csv';
const _reevaluateCsvFileName = 'organiza_downloads_reavaliacao.csv';

class _ScanOptions {
  _ScanOptions({
    required this.root,
    required this.config,
    required this.runMode,
    required this.hashDuplicates,
    required this.verbose,
    required this.csvPath,
    required this.logPath,
    required this.aiOptions,
  });

  final Directory root;
  final OrganizerConfig config;
  final RunMode runMode;
  final bool hashDuplicates;
  final bool verbose;
  final String csvPath;
  final String logPath;
  final AiClassifierOptions? aiOptions;
}

class _MenuState {
  _MenuState() : rootPath = Directory.current.path;

  String rootPath;
  String? csvDirectoryOverride;
  String? logDirectoryOverride;
  RunMode runMode = RunMode.cold;
  bool hashDuplicates = true;
  bool verbose = true;
  String configPath = 'padrao';
  bool rootIsCurrent = true;
  AnalysisMode analysisMode = AnalysisMode.ai;
  DeepSeekModel deepSeekModel = DeepSeekModel.v4Flash;
  String aiCategoryLabel = 'padrao';
  List<String> aiCategories = AiCategoryParser.defaults();
  int aiBatchSize = 150;
  bool aiDebug = false;

  void setRootPath(String value) {
    rootPath = value;
    rootIsCurrent = p.normalize(value) == p.normalize(Directory.current.path);
  }

  void setCsvDirectory(String value) {
    csvDirectoryOverride = value;
  }

  void setLogDirectory(String value) {
    logDirectoryOverride = value;
  }

  bool get csvDirectoryIsDefault => csvDirectoryOverride == null;
  bool get logDirectoryIsDefault => logDirectoryOverride == null;

  String get _defaultReportsDirectory => p.join(
        rootPath,
        OrganizerConfig.defaults().autoOrganizedDirectoryName,
        reportsDirectoryName,
      );

  String get csvDirectoryDisplay =>
      csvDirectoryOverride ?? _defaultReportsDirectory;

  String get logDirectoryDisplay =>
      logDirectoryOverride ?? _defaultReportsDirectory;

  String get csvPreviewPath => p.join(
        csvDirectoryDisplay,
        '<data_hora>_$_defaultCsvFileName',
      );

  String get logPreviewPath => p.join(
        logDirectoryDisplay,
        '<data_hora>_organiza_downloads.log',
      );
}

Future<void> runCli(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Mostra ajuda.',
    )
    ..addOption(
      'config',
      help: 'Caminho para arquivo JSON de regras.',
    )
    ..addOption(
      'csv',
      help: 'Caminho do relatorio CSV. Padrao: '
          '<pasta>/_auto_organizado/logs.',
    )
    ..addOption(
      'log',
      help: 'Caminho do arquivo de log. Padrao: '
          '<pasta>/_auto_organizado/logs.',
    )
    ..addOption(
      'mode',
      allowed: RunMode.values.map((mode) => mode.name),
      defaultsTo: RunMode.cold.name,
      help: 'Modo de execucao: cold so analisa; real move para saidas.',
    )
    ..addFlag(
      'hash-duplicates',
      negatable: false,
      help: 'Calcula SHA-256 em arquivos de mesmo tamanho.',
    )
    ..addFlag(
      'apply',
      negatable: false,
      help: 'Atalho legado para --mode real.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Mostra mais detalhes.',
    )
    ..addFlag(
      'ai',
      negatable: false,
      help: 'Classifica usando IA (DeepSeek) em vez de regras.',
    )
    ..addOption(
      'api-key',
      help: 'Chave DeepSeek. Alternativa: variavel de ambiente '
          'DEEPSEEK_API_KEY.',
    )
    ..addOption(
      'ai-model',
      allowed: ['v4-flash', 'v4-pro'],
      defaultsTo: 'v4-flash',
      help: 'Modelo DeepSeek usado no modo IA.',
    )
    ..addOption(
      'ai-categories',
      help: 'Categorias IA: texto separado por ; ou caminho de arquivo JSON.',
    )
    ..addOption(
      'ai-batch-size',
      defaultsTo: '150',
      help: 'Quantidade de nomes unicos por chamada IA (20 a 500).',
    )
    ..addFlag(
      'ai-debug',
      negatable: false,
      help: 'Salva prompts/respostas da IA na pasta debug/.',
    );

  if (arguments.isEmpty) {
    final options = await _readOptionsFromMenu();
    if (options == null) {
      return;
    }
    await _executeScan(options);
    return;
  }

  if (arguments.first == 'help') {
    _printUsage(parser);
    return;
  }

  final command = arguments.first;
  if (command != 'scan' && command != 'reavaliar') {
    stderr.writeln('Comando desconhecido: $command');
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  late final ArgResults options;
  try {
    options = parser.parse(arguments.skip(1).toList());
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  if (options['help'] as bool) {
    _printUsage(parser);
    return;
  }

  final rest = options.rest;
  if (rest.length > 1) {
    stderr.writeln('Informe no maximo uma pasta para analisar.');
    exitCode = 64;
    return;
  }

  final root = Directory(rest.isEmpty ? Directory.current.path : rest.first);
  late final OrganizerConfig config;
  try {
    config = await OrganizerConfig.load(options['config'] as String?);
  } on FormatException catch (error) {
    stderr.writeln('Configuracao JSON invalida: ${error.message}');
    exitCode = 65;
    return;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return;
  }
  final runMode = _resolveRunMode(options);
  final hashDuplicates = options['hash-duplicates'] as bool;
  final verbose = options['verbose'] as bool;
  final now = DateTime.now();
  final csvPath = _resolveCsvPath(
    options['csv'] as String?,
    p.join(root.path, config.autoOrganizedDirectoryName, reportsDirectoryName),
    now,
  );
  final logPath = _resolveLogPath(
    options['log'] as String?,
    root,
    config,
    now,
  );

  AiClassifierOptions? aiOptions;
  if (options['ai'] as bool) {
    try {
      aiOptions = await _buildAiOptionsFromCli(options);
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      exitCode = 64;
      return;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      if (error.path != null) {
        stderr.writeln(error.path);
      }
      exitCode = 66;
      return;
    }
  }

  final scanOptions = _ScanOptions(
    root: root,
    config: config,
    runMode: runMode,
    hashDuplicates: hashDuplicates,
    verbose: verbose,
    csvPath: csvPath,
    logPath: logPath,
    aiOptions: aiOptions,
  );

  if (command == 'reavaliar') {
    await _executeReevaluate(scanOptions);
  } else {
    await _executeScan(scanOptions);
  }
}

Future<AiClassifierOptions> _buildAiOptionsFromCli(ArgResults options) async {
  final apiKey = (options['api-key'] as String?)?.trim().isNotEmpty == true
      ? (options['api-key'] as String).trim()
      : Platform.environment['DEEPSEEK_API_KEY']?.trim();
  if (apiKey == null || apiKey.isEmpty) {
    throw const FormatException(
      'Modo --ai precisa de --api-key ou da variavel DEEPSEEK_API_KEY.',
    );
  }

  final batchSizeRaw = options['ai-batch-size'] as String;
  final batchSize = int.tryParse(batchSizeRaw);
  if (batchSize == null || batchSize < 20 || batchSize > 500) {
    throw const FormatException(
      '--ai-batch-size precisa ser um numero entre 20 e 500.',
    );
  }

  final categoriesRaw = (options['ai-categories'] as String?)?.trim();
  final categories = categoriesRaw == null || categoriesRaw.isEmpty
      ? AiCategoryParser.defaults()
      : await File(categoriesRaw).exists()
          ? await AiCategoryParser.parseJsonFile(categoriesRaw)
          : AiCategoryParser.parseInline(categoriesRaw);

  final model = switch (options['ai-model'] as String) {
    'v4-pro' => DeepSeekModel.v4Pro,
    _ => DeepSeekModel.v4Flash,
  };

  return AiClassifierOptions(
    apiKey: apiKey,
    model: model,
    categories: categories,
    batchSize: batchSize,
    debugEnabled: options['ai-debug'] as bool,
    debugDirectory: Directory(p.join(Directory.current.path, 'debug')),
    debugRunPrefix: _timestampForFile(DateTime.now()),
  );
}

Future<_ScanOptions?> _readOptionsFromMenu() async {
  final state = _MenuState();
  while (true) {
    _renderMenu(state);
    final choice = _readMenuChoice();
    if (choice == null) {
      return null;
    }

    switch (choice) {
      case '1':
        final options = await _buildScanOptionsFromMenu(state);
        if (options != null) {
          return options;
        }
        continue;
      case '2':
        state.runMode =
            state.runMode == RunMode.cold ? RunMode.real : RunMode.cold;
      case '3':
        final value = _ask('Nova pasta', defaultValue: state.rootPath);
        if (value == null) {
          return null;
        }
        state.setRootPath(value);
      case '4':
        final value = _ask(
          'Pasta do relatorio CSV',
          defaultValue: state.csvDirectoryDisplay,
        );
        if (value == null) {
          return null;
        }
        state.setCsvDirectory(value);
      case '5':
        final value = _ask(
          'Pasta de log',
          defaultValue: state.logDirectoryDisplay,
        );
        if (value == null) {
          return null;
        }
        state.setLogDirectory(value);
      case '6':
        state.hashDuplicates = !state.hashDuplicates;
      case '7':
        state.verbose = !state.verbose;
      case '8':
        final value = _ask(
          'Arquivo de regras JSON',
          defaultValue: state.configPath,
          allowEmpty: true,
        );
        if (value == null) {
          return null;
        }
        state.configPath = value.trim().isEmpty ? 'padrao' : value.trim();
      case '9':
        state.analysisMode = state.analysisMode == AnalysisMode.rules
            ? AnalysisMode.ai
            : AnalysisMode.rules;
      case '10':
        state.deepSeekModel = state.deepSeekModel == DeepSeekModel.v4Flash
            ? DeepSeekModel.v4Pro
            : DeepSeekModel.v4Flash;
      case '11':
        final updated = await _configureAiCategories(state);
        if (!updated) {
          _pause();
        }
      case '12':
        final value = _ask(
          'Tamanho do lote IA',
          defaultValue: state.aiBatchSize.toString(),
        );
        if (value == null) {
          return null;
        }
        final parsed = int.tryParse(value);
        if (parsed == null || parsed < 20 || parsed > 500) {
          stdout.writeln('Use um numero entre 20 e 500.');
          _pause();
        } else {
          state.aiBatchSize = parsed;
        }
      case '13':
        state.aiDebug = !state.aiDebug;
      case '14':
        await _runReevaluateFromMenu(state);
        _pause();
      case '15':
        stdout.writeln('Operacao cancelada.');
        return null;
      default:
        stdout.writeln('Opcao invalida.');
        _pause();
    }
  }
}

void _renderMenu(_MenuState state) {
  _clearScreen();
  stdout.writeln('');
  stdout.writeln('Organiza Downloads');
  stdout.writeln('==================');
  stdout.writeln('');
  stdout.writeln(
    '1. Executar agora  ${_shortSummary(state)}',
  );
  stdout.writeln('');
  stdout.writeln('2. Modo: ${state.runMode.name}');
  stdout.writeln('3. Pasta: ${state.rootPath}');
  stdout.writeln(
    '4. Pasta do relatorio CSV: '
    '${state.csvDirectoryIsDefault ? '${state.csvDirectoryDisplay} (padrao)' : state.csvDirectoryDisplay}',
  );
  stdout.writeln('   Arquivo: ${state.csvPreviewPath}');
  stdout.writeln(
    '5. Pasta de log: '
    '${state.logDirectoryIsDefault ? '${state.logDirectoryDisplay} (padrao)' : state.logDirectoryDisplay}',
  );
  stdout.writeln('   Arquivo: ${state.logPreviewPath}');
  stdout.writeln(
    '6. Duplicatas por hash: ${_yesNoText(state.hashDuplicates)}',
  );
  stdout.writeln('7. Detalhes no final: ${_yesNoText(state.verbose)}');
  stdout.writeln('8. Regras: ${state.configPath}');
  stdout.writeln(
      '9. Analise: ${state.analysisMode == AnalysisMode.ai ? 'IA' : 'regras'}');
  stdout.writeln('10. Modelo IA: ${_modelLabel(state.deepSeekModel)}');
  stdout.writeln('11. Categorias IA: ${state.aiCategoryLabel}');
  stdout.writeln('12. Tamanho lote IA: ${state.aiBatchSize}');
  stdout.writeln('13. Debug IA: ${_yesNoText(state.aiDebug)}');
  stdout.writeln(
    '14. Reavaliar organizados (recategoriza itens ja movidos, ${state.analysisMode == AnalysisMode.ai ? 'IA' : 'regras'}, pasta ${state.rootPath})',
  );
  stdout.writeln('15. Sair');
  stdout.writeln('');
}

void _clearScreen() {
  if (!stdout.hasTerminal) {
    return;
  }
  stdout.write('\x1B[2J\x1B[H');
}

String _shortSummary(_MenuState state) {
  final csv = state.csvDirectoryIsDefault
      ? 'CSV/log em _auto_organizado'
      : 'CSV/log customizados';
  final folder = state.rootIsCurrent ? 'pasta atual' : 'pasta selecionada';
  final analysis = state.analysisMode == AnalysisMode.ai ? 'IA' : 'regras';
  return '[${state.runMode.name} | $analysis | $folder | $csv | hash ${_yesNoText(state.hashDuplicates)}]';
}

String? _readMenuChoice() {
  stdout.write('Escolha [1]: ');
  final input = stdin.readLineSync();
  if (input == null) {
    return null;
  }
  final value = input.trim();
  return value.isEmpty ? '1' : value;
}

String _resolveCsvPath(String? input, String defaultDirectory, DateTime now) {
  final fileName = _timestampedFileName(_defaultCsvFileName, now);
  final value = input?.trim();
  if (value == null || value.isEmpty) {
    return p.join(defaultDirectory, fileName);
  }
  if (_looksLikeDirectory(value)) {
    return p.join(value, fileName);
  }
  return p.join(
    p.dirname(value),
    _timestampedFileName(p.basename(value), now),
  );
}

String _resolveLogPath(
  String? input,
  Directory root,
  OrganizerConfig config,
  DateTime now,
) {
  final fileName = _timestampedFileName('organiza_downloads.log', now);
  final value = input?.trim();
  if (value == null || value.isEmpty) {
    return p.join(
      root.path,
      config.autoOrganizedDirectoryName,
      reportsDirectoryName,
      fileName,
    );
  }
  if (_looksLikeDirectory(value)) {
    return p.join(value, fileName);
  }
  return p.join(
    p.dirname(value),
    _timestampedFileName(p.basename(value), now),
  );
}

bool _looksLikeDirectory(String value) {
  return value.endsWith('/') ||
      value.endsWith('\\') ||
      Directory(value).existsSync() ||
      p.extension(value).isEmpty;
}

Future<_ScanOptions?> _buildScanOptionsFromMenu(_MenuState state) async {
  if (state.runMode == RunMode.real) {
    final confirmed = _askYesNo(
      'Modo real vai mover arquivos. Digite sim para continuar',
      defaultValue: false,
    );
    if (confirmed != true) {
      stdout.writeln('Execucao real cancelada.');
      _pause();
      return null;
    }
  }

  late final OrganizerConfig config;
  try {
    config = await OrganizerConfig.load(
      _isDefaultConfig(state.configPath) ? null : state.configPath,
    );
  } on FormatException catch (error) {
    stderr.writeln('Configuracao JSON invalida: ${error.message}');
    exitCode = 65;
    return null;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return null;
  }

  AiClassifierOptions? aiOptions;
  if (state.analysisMode == AnalysisMode.ai) {
    final confirmed = _askYesNo(
      'Modo IA usa rede e envia nomes dos arquivos ao DeepSeek. Continuar',
      defaultValue: false,
    );
    if (confirmed != true) {
      stdout.writeln('Execucao IA cancelada.');
      _pause();
      return null;
    }
    final apiKey = _resolveApiKeyFromEnvOrPrompt();
    if (apiKey == null || apiKey.isEmpty) {
      stdout.writeln('Chave nao informada.');
      _pause();
      return null;
    }
    aiOptions = AiClassifierOptions(
      apiKey: apiKey,
      model: state.deepSeekModel,
      categories: state.aiCategories,
      batchSize: state.aiBatchSize,
      debugEnabled: state.aiDebug,
      debugDirectory: Directory(p.join(Directory.current.path, 'debug')),
      debugRunPrefix: _timestampForFile(DateTime.now()),
    );
  }

  final now = DateTime.now();
  return _ScanOptions(
    root: Directory(state.rootPath),
    config: config,
    runMode: state.runMode,
    hashDuplicates: state.hashDuplicates,
    verbose: state.verbose,
    csvPath: p.join(
      state.csvDirectoryOverride ??
          p.join(
            state.rootPath,
            config.autoOrganizedDirectoryName,
            reportsDirectoryName,
          ),
      _timestampedFileName(_defaultCsvFileName, now),
    ),
    logPath: p.join(
      state.logDirectoryOverride ??
          p.join(
            state.rootPath,
            config.autoOrganizedDirectoryName,
            reportsDirectoryName,
          ),
      _timestampedFileName('organiza_downloads.log', now),
    ),
    aiOptions: aiOptions,
  );
}

String _timestampedFileName(String fileName, DateTime now) {
  return '${_timestampForFile(now)}_$fileName';
}

String _timestampForFile(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}_'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}';
}

Future<bool> _configureAiCategories(_MenuState state) async {
  stdout.writeln('Categorias IA');
  stdout.writeln('1. Padrao');
  stdout.writeln('2. Texto separado por ponto e virgula');
  stdout.writeln('3. Arquivo JSON');
  stdout.write('Escolha [1]: ');
  final input = stdin.readLineSync();
  final choice = input == null || input.trim().isEmpty ? '1' : input.trim();
  try {
    switch (choice) {
      case '1':
        state.aiCategories = AiCategoryParser.defaults();
        state.aiCategoryLabel = 'padrao';
        return true;
      case '2':
        final value = _ask(
          'Categorias separadas por ;',
          defaultValue: 'documentos; fotos; trabalho; apagar',
        );
        if (value == null) {
          return false;
        }
        state.aiCategories = AiCategoryParser.parseInline(value);
        state.aiCategoryLabel = 'texto (${state.aiCategories.length})';
        return true;
      case '3':
        final value = _ask('Caminho do JSON de categorias', defaultValue: '');
        if (value == null || value.trim().isEmpty) {
          return false;
        }
        state.aiCategories = await AiCategoryParser.parseJsonFile(value.trim());
        state.aiCategoryLabel = 'json (${state.aiCategories.length})';
        return true;
      default:
        stdout.writeln('Opcao invalida.');
        return false;
    }
  } on FormatException catch (error) {
    stdout.writeln('Categorias invalidas: ${error.message}');
    return false;
  } on FileSystemException catch (error) {
    stdout.writeln(error.message);
    if (error.path != null) {
      stdout.writeln(error.path);
    }
    return false;
  }
}

String _yesNoText(bool value) => value ? 'sim' : 'nao';

String _modelLabel(DeepSeekModel model) {
  return switch (model) {
    DeepSeekModel.v4Flash => 'V4 Flash',
    DeepSeekModel.v4Pro => 'V4 Pro',
  };
}

void _pause() {
  stdout.write('Pressione Enter para voltar ao menu...');
  stdin.readLineSync();
}

String? _resolveApiKeyFromEnvOrPrompt() {
  final fromEnv = Platform.environment['DEEPSEEK_API_KEY']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    stdout.writeln('Usando DEEPSEEK_API_KEY do ambiente.');
    return fromEnv;
  }
  return _askSecretMasked('Chave DeepSeek')?.trim();
}

Future<void> _runReevaluateFromMenu(_MenuState state) async {
  if (state.runMode == RunMode.real) {
    final confirmed = _askYesNo(
      'Reavaliar em modo real vai mover os itens reclassificados. Digite sim para continuar',
      defaultValue: false,
    );
    if (confirmed != true) {
      stdout.writeln('Reavaliacao cancelada.');
      return;
    }
  }

  late final OrganizerConfig config;
  try {
    config = await OrganizerConfig.load(
      _isDefaultConfig(state.configPath) ? null : state.configPath,
    );
  } on FormatException catch (error) {
    stderr.writeln('Configuracao JSON invalida: ${error.message}');
    return;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    return;
  }

  AiClassifierOptions? aiOptions;
  if (state.analysisMode == AnalysisMode.ai) {
    final confirmed = _askYesNo(
      'Modo IA usa rede e envia nomes dos arquivos ao DeepSeek. Continuar',
      defaultValue: false,
    );
    if (confirmed != true) {
      stdout.writeln('Reavaliacao IA cancelada.');
      return;
    }
    final apiKey = _resolveApiKeyFromEnvOrPrompt();
    if (apiKey == null || apiKey.isEmpty) {
      stdout.writeln('Chave nao informada.');
      return;
    }
    aiOptions = AiClassifierOptions(
      apiKey: apiKey,
      model: state.deepSeekModel,
      categories: state.aiCategories,
      batchSize: state.aiBatchSize,
      debugEnabled: state.aiDebug,
      debugDirectory: Directory(p.join(Directory.current.path, 'debug')),
      debugRunPrefix: _timestampForFile(DateTime.now()),
    );
  }

  final now = DateTime.now();
  await _executeReevaluate(_ScanOptions(
    root: Directory(state.rootPath),
    config: config,
    runMode: state.runMode,
    hashDuplicates: state.hashDuplicates,
    verbose: state.verbose,
    csvPath: p.join(
      state.csvDirectoryOverride ??
          p.join(
            state.rootPath,
            config.autoOrganizedDirectoryName,
            reportsDirectoryName,
          ),
      _timestampedFileName(_reevaluateCsvFileName, now),
    ),
    logPath: p.join(
      state.logDirectoryOverride ??
          p.join(
            state.rootPath,
            config.autoOrganizedDirectoryName,
            reportsDirectoryName,
          ),
      _timestampedFileName('organiza_downloads_reavaliacao.log', now),
    ),
    aiOptions: aiOptions,
  ));
}

String? _askSecretMasked(String label) {
  stdout.write('$label: ');
  if (!stdin.hasTerminal) {
    return stdin.readLineSync();
  }

  final previousEchoMode = stdin.echoMode;
  final previousLineMode = stdin.lineMode;
  final buffer = StringBuffer();
  stdin
    ..echoMode = false
    ..lineMode = false;
  try {
    while (true) {
      final byte = stdin.readByteSync();
      if (byte == -1) {
        stdout.writeln();
        return null;
      }
      if (byte == 10 || byte == 13) {
        stdout.writeln();
        return buffer.toString();
      }
      if (byte == 3) {
        stdout.writeln();
        return null;
      }
      if (byte == 8 || byte == 127) {
        if (buffer.isNotEmpty) {
          final current = buffer.toString();
          buffer
            ..clear()
            ..write(current.substring(0, current.length - 1));
          stdout.write('\b \b');
        }
        continue;
      }
      buffer.writeCharCode(byte);
      stdout.write('*');
    }
  } finally {
    stdin
      ..lineMode = previousLineMode
      ..echoMode = previousEchoMode;
  }
}

bool _isDefaultConfig(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty || normalized == 'padrao' || normalized == 'padrão';
}

Future<void> _executeScan(_ScanOptions options) async {
  final root = options.root;
  final config = options.config;
  final runMode = options.runMode;
  final hashDuplicates = options.hashDuplicates;
  final verbose = options.verbose;
  final csvPath = options.csvPath;
  final progress = ProgressReporter();
  RunLogger? logger;

  try {
    final aiCalls = <AiCallStats>[];
    late final List<AnalysisResult> results;
    try {
      progress.message('Iniciando organizador de downloads...');
      final analyzer = Analyzer(config);
      results = await analyzer.analyze(
        root,
        hashDuplicates: hashDuplicates,
        aiOptions: options.aiOptions,
        progress: ProgressSink(progress),
        onAiCall: (stats) => _recordAiCall(progress, logger, aiCalls, stats),
        onScanned: (count) async {
          logger = await RunLogger.create(File(options.logPath));
        },
      );
      progress.done('Analise concluida');
    } on FileSystemException catch (error) {
      progress.message('');
      stderr.writeln(error.message);
      if (error.path != null) {
        stderr.writeln(error.path);
      }
      exitCode = 66;
      return;
    }

    if (results.isEmpty) {
      progress.message('');
      stdout.writeln('Nada para organizar em ${root.absolute.path}.');
      return;
    }
    final activeLogger = logger!;

    try {
      progress.determinate('Salvando CSV', 0, 1);
      await CsvReportWriter().write(
        File(csvPath),
        results,
        config: config,
        operation: 'scan',
      );
      progress.determinate('Salvando CSV', 1, 1);
      progress.done('Relatorio salvo');
    } on FileSystemException catch (error) {
      progress.message('');
      stderr.writeln('Nao foi possivel gravar o CSV.');
      stderr.writeln(error.message);
      if (error.path != null) {
        stderr.writeln(error.path);
      }
      stderr.writeln('Use --csv com um caminho onde voce tenha permissao.');
      exitCode = 73;
      return;
    }
    _printSummary(
      logger: activeLogger,
      root: root,
      results: results,
      csvPath: csvPath,
      logPath: options.logPath,
      runMode: runMode,
      hashDuplicates: hashDuplicates,
      verbose: verbose,
    );
    _printAiSummary(activeLogger, aiCalls);

    if (runMode == RunMode.real) {
      await _executeRealMove(
        logger: activeLogger,
        root: root,
        config: config,
        results: results,
        progress: progress,
      );
    } else {
      activeLogger.writeln('');
      activeLogger.writeln('Modo cold concluido.');
      final confirmed = _askConfirmo(
        'Para executar agora em modo real com este mesmo resultado, digite confirmo',
      );
      if (!confirmed) {
        activeLogger.writeln('Execucao real nao iniciada.');
        return;
      }
      await _executeRealMove(
        logger: activeLogger,
        root: root,
        config: config,
        results: results,
        progress: progress,
      );
    }
  } finally {
    await logger?.close();
  }
}

Future<void> _executeRealMove({
  required RunLogger logger,
  required Directory root,
  required OrganizerConfig config,
  required List<AnalysisResult> results,
  required ProgressReporter progress,
}) async {
  if (!await _canWriteTo(root)) {
    stderr.writeln('');
    stderr.writeln('Nao foi possivel rodar em modo real.');
    stderr.writeln('A pasta analisada nao permite escrita.');
    stderr.writeln(root.absolute.path);
    stderr.writeln(
      'Rode em modo cold para gerar relatorio ou ajuste a permissao/montagem da pasta.',
    );
    exitCode = 73;
    return;
  }

  final summary = await QuarantineMover(config).moveAll(
    results,
    root: root,
    onMove: (current, total) {
      progress.determinate('Movendo arquivos', current, total);
    },
  );
  progress.done('Arquivos movidos');
  final removedDirectories = await EmptyDirectoryCleaner(config).clean(root);
  logger.writeln('');
  logger.writeln(
    'Arquivos em ${config.quarantineDirectoryName}: ${summary.quarantined}',
  );
  logger.writeln(
    'Arquivos em ${config.autoOrganizedDirectoryName}: ${summary.organized}',
  );
  logger.writeln(
    'Arquivos ignorados porque nao existiam mais: ${summary.skipped}',
  );
  logger.writeln(
    'Pastas vazias removidas: $removedDirectories',
  );
}

Future<void> _executeReevaluate(_ScanOptions options) async {
  final root = options.root;
  final config = options.config;
  final runMode = options.runMode;
  final hashDuplicates = options.hashDuplicates;
  final verbose = options.verbose;
  final csvPath = options.csvPath;
  final progress = ProgressReporter();
  RunLogger? logger;

  try {
    if (runMode == RunMode.real && !await _canWriteTo(root)) {
      stderr.writeln('');
      stderr.writeln('Nao foi possivel reavaliar em modo real.');
      stderr.writeln('A pasta analisada nao permite escrita.');
      stderr.writeln(root.absolute.path);
      stderr.writeln(
        'Rode em modo cold para gerar relatorio ou ajuste a permissao/montagem da pasta.',
      );
      exitCode = 73;
      return;
    }

    final aiCalls = <AiCallStats>[];
    late final List<AnalysisResult> results;
    late final ReevaluateSummary summary;
    try {
      progress.message('Reavaliando itens ja organizados...');
      final (analysisResults, reevaluateSummary) =
          await Reevaluator(config).run(
        root,
        hashDuplicates: hashDuplicates,
        applyMoves: runMode == RunMode.real,
        aiOptions: options.aiOptions,
        progress: ProgressSink(progress),
        onAiCall: (stats) => _recordAiCall(progress, logger, aiCalls, stats),
        onScanned: (count) async {
          logger = await RunLogger.create(File(options.logPath));
        },
      );
      results = analysisResults;
      summary = reevaluateSummary;
      progress.done('Reavaliacao concluida');
    } on FileSystemException catch (error) {
      progress.message('');
      stderr.writeln(error.message);
      if (error.path != null) {
        stderr.writeln(error.path);
      }
      exitCode = 66;
      return;
    }

    if (results.isEmpty) {
      progress.message('');
      stdout.writeln(
        'Nenhum item encontrado em ${config.quarantineDirectoryName} ou '
        '${config.autoOrganizedDirectoryName} para reavaliar.',
      );
      return;
    }
    final activeLogger = logger!;

    try {
      progress.determinate('Salvando CSV', 0, 1);
      await CsvReportWriter().write(
        File(csvPath),
        results,
        config: config,
        operation: 'reavaliacao',
      );
      progress.determinate('Salvando CSV', 1, 1);
      progress.done('Relatorio salvo');
    } on FileSystemException catch (error) {
      progress.message('');
      stderr.writeln('Nao foi possivel gravar o CSV.');
      stderr.writeln(error.message);
      if (error.path != null) {
        stderr.writeln(error.path);
      }
      stderr.writeln('Use --csv com um caminho onde voce tenha permissao.');
      exitCode = 73;
      return;
    }

    activeLogger.writeln('');
    activeLogger.writeln('Pasta: ${root.absolute.path}');
    activeLogger.writeln('Itens reavaliados: ${summary.total}');
    activeLogger.writeln('Reclassificados: ${summary.recategorized}');
    activeLogger.writeln('Sem mudanca: ${summary.unchanged}');
    activeLogger.writeln('CSV: $csvPath');
    activeLogger.writeln('Log: ${options.logPath}');
    activeLogger.writeln(
      'Modo: ${runMode == RunMode.real ? 'real (moveu os reclassificados)' : 'cold (so relatorio, nada foi movido)'}',
    );
    _printAiSummary(activeLogger, aiCalls);

    if (verbose) {
      activeLogger.writeln('');
      activeLogger.writeln('Categorias apos reavaliacao:');
      final categories = <String, int>{};
      for (final result in results) {
        categories[result.category] = (categories[result.category] ?? 0) + 1;
      }
      final ordered = categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final item in ordered) {
        activeLogger.writeln('- ${item.key}: ${item.value}');
      }
    }

    if (runMode == RunMode.real) {
      final removedDirectories =
          await EmptyDirectoryCleaner(config).clean(root);
      activeLogger.writeln('Pastas vazias removidas: $removedDirectories');
    }
  } finally {
    await logger?.close();
  }
}

String? _ask(
  String label, {
  required String defaultValue,
  bool allowEmpty = false,
}) {
  final suffix = defaultValue.isEmpty ? '' : ' [$defaultValue]';
  stdout.write('$label$suffix: ');
  final input = stdin.readLineSync();
  if (input == null) {
    return null;
  }
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    if (defaultValue.isNotEmpty || allowEmpty) {
      return defaultValue;
    }
    return _ask(label, defaultValue: defaultValue, allowEmpty: allowEmpty);
  }
  return trimmed;
}

bool? _askYesNo(String label, {required bool defaultValue}) {
  final defaultText = defaultValue ? 'S/n' : 's/N';
  while (true) {
    stdout.write('$label [$defaultText]: ');
    final input = stdin.readLineSync();
    if (input == null) {
      return null;
    }
    final value = input.trim().toLowerCase();
    if (value.isEmpty) {
      return defaultValue;
    }
    if (value == 's' || value == 'sim' || value == 'y' || value == 'yes') {
      return true;
    }
    if (value == 'n' || value == 'nao' || value == 'não' || value == 'no') {
      return false;
    }
    stdout.writeln('Responda sim ou nao.');
  }
}

bool _askConfirmo(String label) {
  stdout.write('$label: ');
  final input = stdin.readLineSync();
  return input?.trim() == 'confirmo';
}

RunMode _resolveRunMode(ArgResults options) {
  if (options['apply'] as bool) {
    return RunMode.real;
  }
  final modeName = options['mode'] as String;
  return RunMode.values.firstWhere((mode) => mode.name == modeName);
}

Future<bool> _canWriteTo(Directory directory) async {
  final probe = File(
    p.join(
      directory.absolute.path,
      '.organiza_downloads_write_test_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  try {
    await probe.writeAsString('ok');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln('Uso: organiza_downloads <scan|reavaliar> [pasta] [opcoes]');
  stdout.writeln('');
  stdout.writeln(
    'scan: analisa itens diretos da pasta e classifica.',
  );
  stdout.writeln(
    'reavaliar: reclassifica itens ja movidos para dentro de '
    '_organiza_quarentena/_auto_organizado, varrendo todas as '
    'subpastas de categoria de uma vez; so move o que mudou de categoria.',
  );
  stdout.writeln('');
  stdout.writeln('Opcoes:');
  stdout.writeln(parser.usage);
}

void _printSummary({
  required RunLogger logger,
  required Directory root,
  required List<AnalysisResult> results,
  required String csvPath,
  required String logPath,
  required RunMode runMode,
  required bool hashDuplicates,
  required bool verbose,
}) {
  final summary = ScanSummary(results);
  logger.writeln('Pasta: ${root.absolute.path}');
  logger.writeln('Arquivos analisados: ${summary.totalFiles}');
  logger.writeln('Tamanho total: ${_formatBytes(summary.totalBytes)}');
  logger.writeln('CSV: $csvPath');
  logger.writeln('Log: $logPath');
  logger.writeln(
    'Modo: ${runMode == RunMode.real ? 'real' : 'cold'}',
  );
  logger.writeln(
    'Duplicatas: ${hashDuplicates ? 'confirmadas por hash' : 'somente tamanho'}',
  );
  logger.writeln('');
  logger.writeln('Acoes sugeridas:');

  for (final action in FileAction.values) {
    final count = summary.actionCounts[action] ?? 0;
    final bytes = summary.actionBytes[action] ?? 0;
    logger.writeln(
      '- ${action.name}: $count arquivos (${_formatBytes(bytes)})',
    );
  }

  if (!verbose) {
    return;
  }

  logger.writeln('');
  logger.writeln('Categorias:');
  final categories = <String, int>{};
  for (final result in results) {
    categories[result.category] = (categories[result.category] ?? 0) + 1;
  }
  final ordered = categories.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final item in ordered) {
    logger.writeln('- ${item.key}: ${item.value}');
  }
}

void _recordAiCall(
  ProgressReporter progress,
  RunLogger? logger,
  List<AiCallStats> calls,
  AiCallStats stats,
) {
  calls.add(stats);
  final durationText = '${stats.duration.inMilliseconds}ms';
  final tokensText =
      stats.totalTokens != null ? ', ${stats.totalTokens} tokens' : '';
  final statusText = stats.statusCode < 200 || stats.statusCode >= 300
      ? ' (HTTP ${stats.statusCode})'
      : '';
  final line = 'IA ${stats.label}: $durationText$tokensText$statusText';
  progress.message(line);
  logger?.fileOnly(line);
}

void _printAiSummary(RunLogger logger, List<AiCallStats> calls) {
  if (calls.isEmpty) {
    return;
  }
  final totalDuration = calls.fold<Duration>(
    Duration.zero,
    (total, call) => total + call.duration,
  );
  final totalTokens = calls.fold<int>(
    0,
    (total, call) => total + (call.totalTokens ?? 0),
  );
  final totalPromptTokens = calls.fold<int>(
    0,
    (total, call) => total + (call.promptTokens ?? 0),
  );
  final totalCompletionTokens = calls.fold<int>(
    0,
    (total, call) => total + (call.completionTokens ?? 0),
  );

  logger.writeln('');
  logger.writeln('IA (DeepSeek):');
  logger.writeln('- Chamadas: ${calls.length}');
  logger.writeln(
    '- Tempo total: ${(totalDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
  );
  logger.writeln(
    '- Tempo medio por chamada: '
    '${(totalDuration.inMilliseconds / calls.length).toStringAsFixed(0)}ms',
  );
  logger.writeln(
    '- Tokens totais: $totalTokens (prompt $totalPromptTokens + '
    'completion $totalCompletionTokens)',
  );
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
