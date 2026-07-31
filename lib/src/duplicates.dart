import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:organiza_downloads/src/models.dart';

class DuplicateDetector {
  Future<void> markDuplicates(
    List<AnalysisResult> results, {
    required bool hashDuplicates,
    void Function()? onHashFile,
  }) async {
    final bySize = <int, List<AnalysisResult>>{};
    for (final result in results) {
      if (!result.entry.isFile) {
        continue;
      }
      bySize.putIfAbsent(result.entry.sizeBytes, () => []).add(result);
    }

    var groupCounter = 1;
    for (final group in bySize.values.where((items) => items.length > 1)) {
      if (hashDuplicates) {
        final byHash = <String, List<AnalysisResult>>{};
        for (final result in group) {
          final hash = await _sha256(result.entry.file);
          onHashFile?.call();
          result.hash = hash;
          byHash.putIfAbsent(hash, () => []).add(result);
        }
        for (final hashGroup
            in byHash.values.where((items) => items.length > 1)) {
          _markGroup(hashGroup, 'dup-${groupCounter++}', confirmed: true);
        }
      } else {
        for (final result in group) {
          result.duplicateGroup ??= 'same-size';
        }
      }
    }

    _markCopyNameGroups(results);
  }

  void _markGroup(
    List<AnalysisResult> group,
    String groupId, {
    required bool confirmed,
  }) {
    group.sort((a, b) {
      final copyOrder =
          _copyIndexFor(a.entry.name).compareTo(_copyIndexFor(b.entry.name));
      if (copyOrder != 0) {
        return copyOrder;
      }
      final modified = a.entry.modifiedAt.compareTo(b.entry.modifiedAt);
      if (modified != 0) {
        return modified;
      }
      return a.entry.relativePath.compareTo(b.entry.relativePath);
    });

    for (var index = 0; index < group.length; index++) {
      final result = group[index];
      result.duplicateGroup = groupId;
      if (index == 0) {
        result.reason = '${result.reason}; copia mantida do grupo duplicado';
        continue;
      }

      if (confirmed) {
        final previous = '${result.action.name}/${result.category}';
        result.action = FileAction.quarantine;
        result.category = 'duplicados';
        result.risk = RiskLevel.low;
        result.reason =
            'duplicata confirmada por hash; classificacao anterior: $previous';
      } else {
        result.reason = '${result.reason}; possivel duplicata por tamanho';
      }
    }
  }

  void _markCopyNameGroups(List<AnalysisResult> results) {
    final byBaseName = <String, List<_CopyNameMatch>>{};
    for (final result in results) {
      final match = _copyNameMatch(result);
      if (match == null) {
        continue;
      }
      byBaseName.putIfAbsent(match.baseKey, () => []).add(match);
    }

    var counter = 1;
    for (final group in byBaseName.values.where(_hasLikelyCopies)) {
      group.sort((a, b) {
        final copyOrder = a.copyIndex.compareTo(b.copyIndex);
        if (copyOrder != 0) {
          return copyOrder;
        }
        final modified =
            a.result.entry.modifiedAt.compareTo(b.result.entry.modifiedAt);
        if (modified != 0) {
          return modified;
        }
        return a.result.entry.relativePath.compareTo(
          b.result.entry.relativePath,
        );
      });

      final groupId = 'name-dup-${counter++}';
      final hasOriginal = group.any((item) => item.copyIndex == 0);
      var keptCopyWithoutOriginal = false;
      for (final item in group) {
        final result = item.result;
        if (item.copyIndex == 0) {
          result.duplicateGroup ??= groupId;
          result.reason =
              '${result.reason}; referencia para copias com mesmo nome base';
          continue;
        }
        if (!hasOriginal && !keptCopyWithoutOriginal) {
          keptCopyWithoutOriginal = true;
          result.duplicateGroup ??= groupId;
          result.reason =
              '${result.reason}; primeira copia mantida por falta do original';
          continue;
        }
        if (_isConfirmedHashDuplicate(result)) {
          continue;
        }

        final previous = '${result.action.name}/${result.category}';
        result.duplicateGroup ??= groupId;
        result.action = FileAction.quarantine;
        result.category = 'duplicados';
        result.risk =
            result.entry.isDirectory ? RiskLevel.medium : RiskLevel.low;
        result.reason =
            'duplicata provavel pelo nome; classificacao anterior: $previous; confirme antes de apagar';
      }
    }
  }

  bool _hasLikelyCopies(List<_CopyNameMatch> group) {
    final hasCopy = group.any((item) => item.copyIndex > 0);
    if (!hasCopy) {
      return false;
    }
    final hasOriginal = group.any((item) => item.copyIndex == 0);
    return hasOriginal || group.where((item) => item.copyIndex > 0).length > 1;
  }

  bool _isConfirmedHashDuplicate(AnalysisResult result) {
    return result.action == FileAction.quarantine &&
        result.category == 'duplicados' &&
        result.reason.contains('duplicata confirmada por hash');
  }

  _CopyNameMatch? _copyNameMatch(AnalysisResult result) {
    final name = result.entry.name.trim();
    if (name.isEmpty) {
      return null;
    }

    final extensionStart = result.entry.isFile ? name.lastIndexOf('.') : -1;
    final hasExtension = extensionStart > 0 && extensionStart < name.length - 1;
    final stem = hasExtension ? name.substring(0, extensionStart) : name;
    final extension = hasExtension ? name.substring(extensionStart) : '';
    final normalizedStem = stem.trim().toLowerCase();
    final normalizedExtension = extension.toLowerCase();

    final match = RegExp(r'^(.*?)[ ]*\(([0-9]+)\)$').firstMatch(stem.trim());
    if (match == null) {
      return _CopyNameMatch(
        result: result,
        baseKey: '$normalizedStem$normalizedExtension',
        copyIndex: 0,
      );
    }

    final baseStem = match.group(1)!.trim().toLowerCase();
    if (baseStem.isEmpty) {
      return null;
    }
    final copyIndex = int.tryParse(match.group(2)!);
    if (copyIndex == null || copyIndex <= 0) {
      return null;
    }
    return _CopyNameMatch(
      result: result,
      baseKey: '$baseStem$normalizedExtension',
      copyIndex: copyIndex,
    );
  }

  int _copyIndexFor(String name) {
    final extensionStart = name.lastIndexOf('.');
    final hasExtension = extensionStart > 0 && extensionStart < name.length - 1;
    final stem = hasExtension ? name.substring(0, extensionStart) : name;
    final match = RegExp(r'^(.*?)[ ]*\(([0-9]+)\)$').firstMatch(stem.trim());
    if (match == null) {
      return 0;
    }
    final copyIndex = int.tryParse(match.group(2)!);
    if (copyIndex == null || copyIndex <= 0) {
      return 0;
    }
    return copyIndex;
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

class _CopyNameMatch {
  _CopyNameMatch({
    required this.result,
    required this.baseKey,
    required this.copyIndex,
  });

  final AnalysisResult result;
  final String baseKey;
  final int copyIndex;
}
