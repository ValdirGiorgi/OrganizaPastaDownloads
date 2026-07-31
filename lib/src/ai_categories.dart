import 'dart:convert';
import 'dart:io';

import 'package:organiza_downloads/src/ai_classifier.dart';

class AiCategoryParser {
  static List<String> defaults() => List.of(AiClassifier.defaultCategories);

  static List<String> parseInline(String value) {
    return _normalize(value.split(';'));
  }

  static Future<List<String>> parseJsonFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Arquivo de categorias nao encontrado', path);
    }
    final decoded = jsonDecode(await file.readAsString());
    final raw = switch (decoded) {
      {'categories': final List categories} => categories,
      final List categories => categories,
      _ => throw const FormatException(
          'JSON deve ser um array ou objeto com chave categories',
        ),
    };
    return _normalize(raw.whereType<String>());
  }

  static List<String> _normalize(Iterable<String> values) {
    final categories = <String>{};
    for (final value in values) {
      final normalized =
          value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      if (normalized.isEmpty) {
        continue;
      }
      if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(normalized)) {
        continue;
      }
      categories.add(normalized);
    }

    final withoutOutros = categories.where((item) => item != 'outros').toList();
    if (withoutOutros.length < 2) {
      throw const FormatException('Informe pelo menos 2 categorias validas');
    }
    categories.add('outros');
    return categories.toList()..sort();
  }
}
