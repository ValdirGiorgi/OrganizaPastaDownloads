import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:organiza_downloads/src/models.dart';

enum AnalysisMode {
  rules,
  ai,
}

enum DeepSeekModel {
  v4Flash,
  v4Pro,
}

class AiClassifierOptions {
  AiClassifierOptions({
    required this.apiKey,
    required this.model,
    required this.categories,
    required this.batchSize,
    required this.debugEnabled,
    required this.debugDirectory,
    required this.debugRunPrefix,
  });

  final String apiKey;
  final DeepSeekModel model;
  final List<String> categories;
  final int batchSize;
  final bool debugEnabled;
  final Directory debugDirectory;
  final String debugRunPrefix;
}

class AiCallStats {
  AiCallStats({
    required this.label,
    required this.duration,
    required this.statusCode,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final String label;
  final Duration duration;
  final int statusCode;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

class AiUsageSummary {
  final List<AiCallStats> calls = [];

  int get callCount => calls.length;

  Duration get totalDuration => calls.fold(
        Duration.zero,
        (total, call) => total + call.duration,
      );

  int get totalTokens => calls.fold(
        0,
        (total, call) => total + (call.totalTokens ?? 0),
      );

  int get totalPromptTokens => calls.fold(
        0,
        (total, call) => total + (call.promptTokens ?? 0),
      );

  int get totalCompletionTokens => calls.fold(
        0,
        (total, call) => total + (call.completionTokens ?? 0),
      );
}

class AiClassifier {
  AiClassifier({
    HttpClient? client,
    Uri? endpoint,
  })  : _client = client ?? HttpClient(),
        _endpoint =
            endpoint ?? Uri.parse('https://api.deepseek.com/chat/completions');

  static const defaultCategories = [
    'financeiro_fiscal',
    'saude',
    'documentos',
    'imagens',
    'videos_audio',
    'modelos_3d',
    'instaladores',
    'backups',
    'codigo',
    'temporarios',
    'duplicados',
    'outros',
  ];

  final HttpClient _client;
  final Uri _endpoint;

  Future<AiUsageSummary> classify(
    List<AnalysisResult> results, {
    required AiClassifierOptions options,
    void Function(int current, int total)? onBatch,
    void Function(String label, int current, int total)? onBatchStatus,
    void Function(AiCallStats stats)? onCall,
  }) async {
    final usage = AiUsageSummary();
    if (results.isEmpty) {
      return usage;
    }

    final byName = <String, List<AnalysisResult>>{};
    for (final result in results) {
      byName
          .putIfAbsent(_normalizeName(result.entry.name), () => [])
          .add(result);
    }

    final uniqueNames =
        byName.values.map((items) => items.first.entry.name).toList()..sort();

    void recordCall(AiCallStats stats) {
      usage.calls.add(stats);
      onCall?.call(stats);
    }

    final batches = _chunks(uniqueNames, options.batchSize);
    for (var index = 0; index < batches.length; index++) {
      final current = index + 1;
      final total = batches.length;
      final batch = batches[index];
      onBatch?.call(current, total);
      onBatchStatus?.call(
        'Enviando IA lote $current/$total (${batch.length} nomes)',
        current,
        total,
      );
      Timer? waitingTimer;
      try {
        waitingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
          onBatchStatus?.call(
            'Aguardando DeepSeek lote $current/$total',
            current,
            total,
          );
        });
        final classifications = await _classifyBatchWithRetry(
          batch,
          options: options,
          label: 'batch_${current.toString().padLeft(3, '0')}',
          onCall: recordCall,
        );
        waitingTimer.cancel();
        onBatchStatus?.call(
          'Aplicando resposta IA lote $current/$total',
          current,
          total,
        );
        _applyClassifications(classifications, byName);
      } finally {
        waitingTimer?.cancel();
      }
    }
    return usage;
  }

  void _applyClassifications(
    List<_AiClassification> classifications,
    Map<String, List<AnalysisResult>> byName,
  ) {
    for (final item in classifications) {
      final group = byName[_normalizeName(item.name)];
      if (group == null) {
        continue;
      }
      for (final result in group) {
        result.action = item.action;
        result.category = item.category;
        result.risk = item.risk;
        result.reason = 'ia: ${item.reason}';
      }
    }
  }

  Future<List<_AiClassification>> _classifyBatchWithRetry(
    List<String> names, {
    required AiClassifierOptions options,
    required String label,
    void Function(AiCallStats stats)? onCall,
  }) async {
    try {
      return await _classifyBatch(
        names,
        options: options,
        label: label,
        onCall: onCall,
      );
    } on _AiBatchException catch (error) {
      await _writeDebugError(options, label, error.toString());
      if (!error.retryable) {
        return const [];
      }
      return _splitAndRetry(
        names,
        options: options,
        label: label,
        onCall: onCall,
      );
    } on Object {
      return _splitAndRetry(
        names,
        options: options,
        label: label,
        onCall: onCall,
      );
    }
  }

  Future<List<_AiClassification>> _splitAndRetry(
    List<String> names, {
    required AiClassifierOptions options,
    required String label,
    void Function(AiCallStats stats)? onCall,
  }) async {
    if (names.length <= 1) {
      return const [];
    }
    final middle = names.length ~/ 2;
    final left = await _classifyBatchWithRetry(
      names.sublist(0, middle),
      options: options,
      label: '${label}_a',
      onCall: onCall,
    );
    final right = await _classifyBatchWithRetry(
      names.sublist(middle),
      options: options,
      label: '${label}_b',
      onCall: onCall,
    );
    return [...left, ...right];
  }

  Future<List<_AiClassification>> _classifyBatch(
    List<String> names, {
    required AiClassifierOptions options,
    required String label,
    void Function(AiCallStats stats)? onCall,
  }) async {
    final requestPayload = {
      'model': _modelId(options.model),
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': _systemPrompt(options.categories),
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'file_names': names,
          }),
        },
      ],
    };
    await _writeDebugPrompt(options, label, requestPayload);

    final stopwatch = Stopwatch()..start();
    final request = await _client.postUrl(_endpoint);
    request.headers.contentType = ContentType.json;
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${options.apiKey}');

    request.write(jsonEncode(requestPayload));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    stopwatch.stop();
    await _writeDebugResponse(options, label, response.statusCode, body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      onCall?.call(AiCallStats(
        label: label,
        duration: stopwatch.elapsed,
        statusCode: response.statusCode,
      ));
      throw _AiBatchException(
        'DeepSeek retornou HTTP ${response.statusCode}: $body',
        retryable: _isRetryableStatus(response.statusCode),
      );
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final usage = decoded['usage'];
    onCall?.call(AiCallStats(
      label: label,
      duration: stopwatch.elapsed,
      statusCode: response.statusCode,
      promptTokens: usage is Map ? usage['prompt_tokens'] as int? : null,
      completionTokens:
          usage is Map ? usage['completion_tokens'] as int? : null,
      totalTokens: usage is Map ? usage['total_tokens'] as int? : null,
    ));

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Resposta sem choices');
    }
    final message = choices.first['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Resposta sem message');
    }
    final content = message['content'];
    if (content is! String) {
      throw const FormatException('Resposta sem content');
    }

    return _parseContent(content, options.categories);
  }

  List<_AiClassification> _parseContent(
    String content,
    List<String> categories,
  ) {
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    final items = decoded['items'];
    if (items is! List) {
      throw const FormatException('JSON da IA sem items');
    }

    final allowedCategories = categories.toSet();
    final parsed = <_AiClassification>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final name = item['name'];
      final category = item['category'];
      final action = item['action'];
      final risk = item['risk'];
      final reason = item['reason'];
      if (name is! String ||
          category is! String ||
          action is! String ||
          risk is! String ||
          reason is! String) {
        continue;
      }
      if (!allowedCategories.contains(category)) {
        continue;
      }
      final parsedAction = _parseAction(action);
      final parsedRisk = _parseRisk(risk);
      if (parsedAction == null || parsedRisk == null) {
        continue;
      }
      parsed.add(_AiClassification(
        name: name,
        category: category,
        action: parsedAction,
        risk: parsedRisk,
        reason: reason,
      ));
    }
    return parsed;
  }

  String _systemPrompt(List<String> categories) {
    return '''
Voce classifica itens diretos de uma pasta Downloads olhando somente o nome.
A lista pode conter arquivos e pastas do primeiro nivel.
Quando o item for uma pasta, classifique a pasta inteira pelo nome; nao assuma nem solicite conteudo interno.
Nao invente categorias. Use apenas as categorias permitidas.
Categorias permitidas: ${categories.join(', ')}.
Acoes permitidas: keep, review, quarantine.
Riscos permitidos: low, medium, high.
Responda somente JSON valido, sem markdown, no formato:
{"items":[{"name":"arquivo.pdf","category":"documentos","action":"review","risk":"medium","reason":"motivo curto"}]}
Use "quarantine" apenas para itens claramente temporarios, instaladores, caches ou descartaveis pelo nome.
Quando o nome indicar copia, como "arquivo (1).pdf", "arquivo(2).pdf" ou "pasta (1)", prefira category "duplicados" e action "quarantine"; se parecer pessoal, fiscal ou saude, use "review".
Use "keep" para documentos pessoais, fiscais, financeiros, saude ou itens claramente importantes.
Use "review" quando houver duvida.
''';
  }

  Future<void> _writeDebugPrompt(
    AiClassifierOptions options,
    String label,
    Map<String, dynamic> payload,
  ) async {
    if (!options.debugEnabled) {
      return;
    }
    await options.debugDirectory.create(recursive: true);
    final file = File(
      '${options.debugDirectory.path}/${options.debugRunPrefix}_${label}_prompt.txt',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'endpoint': _endpoint.toString(),
        'authorization': 'Bearer <redacted>',
        'payload': payload,
      }),
    );
  }

  Future<void> _writeDebugResponse(
    AiClassifierOptions options,
    String label,
    int statusCode,
    String body,
  ) async {
    if (!options.debugEnabled) {
      return;
    }
    await options.debugDirectory.create(recursive: true);
    final file = File(
      '${options.debugDirectory.path}/${options.debugRunPrefix}_${label}_response.txt',
    );
    await file.writeAsString('HTTP $statusCode\n\n$body');
  }

  Future<void> _writeDebugError(
    AiClassifierOptions options,
    String label,
    String error,
  ) async {
    if (!options.debugEnabled) {
      return;
    }
    await options.debugDirectory.create(recursive: true);
    final file = File(
      '${options.debugDirectory.path}/${options.debugRunPrefix}_${label}_error.txt',
    );
    await file.writeAsString(error);
  }

  List<List<String>> _chunks(List<String> items, int size) {
    final chunks = <List<String>>[];
    for (var index = 0; index < items.length; index += size) {
      final end = index + size > items.length ? items.length : index + size;
      chunks.add(items.sublist(index, end));
    }
    return chunks;
  }

  String _modelId(DeepSeekModel model) {
    return switch (model) {
      DeepSeekModel.v4Flash => 'deepseek-v4-flash',
      DeepSeekModel.v4Pro => 'deepseek-v4-pro',
    };
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  String _normalizeName(String name) => name.trim().toLowerCase();

  FileAction? _parseAction(String value) {
    for (final action in FileAction.values) {
      if (action.name == value) {
        return action;
      }
    }
    return null;
  }

  RiskLevel? _parseRisk(String value) {
    for (final risk in RiskLevel.values) {
      if (risk.name == value) {
        return risk;
      }
    }
    return null;
  }
}

class _AiBatchException implements Exception {
  _AiBatchException(this.message, {required this.retryable});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

class _AiClassification {
  _AiClassification({
    required this.name,
    required this.category,
    required this.action,
    required this.risk,
    required this.reason,
  });

  final String name;
  final String category;
  final FileAction action;
  final RiskLevel risk;
  final String reason;
}
