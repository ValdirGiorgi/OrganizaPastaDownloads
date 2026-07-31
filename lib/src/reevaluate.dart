import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:organiza_downloads/src/ai_classifier.dart';
import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/duplicates.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:organiza_downloads/src/progress.dart';
import 'package:organiza_downloads/src/quarantine.dart';
import 'package:organiza_downloads/src/rules.dart';
import 'package:organiza_downloads/src/scanner.dart';

class ReevaluateCandidate {
  ReevaluateCandidate({
    required this.entry,
    required this.originManagedDirectory,
    required this.originCategory,
  });

  final FileEntry entry;
  final String originManagedDirectory;
  final String originCategory;
}

class ReevaluateSummary {
  ReevaluateSummary({
    required this.total,
    required this.recategorized,
    required this.unchanged,
  });

  final int total;
  final int recategorized;
  final int unchanged;
}

/// Nome reservado da subpasta onde CSV e log ficam guardados dentro de
/// cada pasta gerenciada; nunca e tratada como categoria na reavaliacao.
const reportsDirectoryName = 'logs';

class ReevaluateScanner {
  ReevaluateScanner(this.config);

  final OrganizerConfig config;

  Future<List<ReevaluateCandidate>> scan(Directory root) async {
    final normalizedRoot = Directory(p.normalize(root.absolute.path));
    final candidates = <ReevaluateCandidate>[];

    for (final managedName in [
      config.quarantineDirectoryName,
      config.autoOrganizedDirectoryName,
    ]) {
      final managedDirectory =
          Directory(p.join(normalizedRoot.path, managedName));
      if (!await managedDirectory.exists()) {
        continue;
      }

      await for (final categoryEntity in managedDirectory.list(
        recursive: false,
        followLinks: false,
      )) {
        if (categoryEntity is! Directory) {
          continue;
        }
        final category = p.basename(categoryEntity.path);
        if (category == reportsDirectoryName) {
          continue;
        }

        await for (final itemEntity in categoryEntity.list(
          recursive: false,
          followLinks: false,
        )) {
          if (itemEntity is! File && itemEntity is! Directory) {
            continue;
          }
          final stat = await itemEntity.stat();
          final basename = p.basename(itemEntity.path);
          candidates.add(ReevaluateCandidate(
            entry: FileEntry(
              entity: itemEntity,
              type:
                  itemEntity is Directory ? EntryType.directory : EntryType.file,
              root: normalizedRoot,
              relativePath: basename,
              name: basename,
              extension:
                  itemEntity is Directory ? '' : extensionOf(basename),
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
            ),
            originManagedDirectory: managedName,
            originCategory: category,
          ));
        }
      }
    }

    candidates.sort(
      (a, b) => a.entry.relativePath.compareTo(b.entry.relativePath),
    );
    return candidates;
  }
}

class Reevaluator {
  Reevaluator(this.config);

  final OrganizerConfig config;

  Future<(List<AnalysisResult>, ReevaluateSummary)> run(
    Directory root, {
    required bool hashDuplicates,
    required bool applyMoves,
    AiClassifierOptions? aiOptions,
    ProgressSink? progress,
    void Function(AiCallStats stats)? onAiCall,
    Future<void> Function(int count)? onScanned,
  }) async {
    final candidates = await ReevaluateScanner(config).scan(root);
    if (candidates.isEmpty) {
      return (
        const <AnalysisResult>[],
        ReevaluateSummary(total: 0, recategorized: 0, unchanged: 0),
      );
    }
    await onScanned?.call(candidates.length);

    final classifier = RuleClassifier(config);
    final results = <AnalysisResult>[];
    for (final candidate in candidates) {
      results.add(classifier.classify(candidate.entry));
      progress?.classifyingFile(candidates.length);
    }

    if (aiOptions != null && results.isNotEmpty) {
      await AiClassifier().classify(
        results,
        options: aiOptions,
        onBatch: (current, total) {
          progress?.reporter.determinate('Classificando IA', current, total);
        },
        onBatchStatus: (label, current, total) {
          progress?.reporter.determinate(label, current, total);
        },
        onCall: onAiCall,
      );
    }

    await DuplicateDetector().markDuplicates(
      results,
      hashDuplicates: hashDuplicates,
    );

    final toMove = <AnalysisResult>[];
    var unchanged = 0;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final result = results[index];
      final newManagedDirectory = result.action == FileAction.quarantine
          ? config.quarantineDirectoryName
          : config.autoOrganizedDirectoryName;
      result.origin = p.join(candidate.originManagedDirectory, candidate.originCategory);
      final changed = newManagedDirectory != candidate.originManagedDirectory ||
          result.category != candidate.originCategory;
      if (changed) {
        toMove.add(result);
      } else {
        unchanged++;
      }
    }

    if (applyMoves && toMove.isNotEmpty) {
      await QuarantineMover(config).moveAll(
        toMove,
        root: root,
        onMove: (current, total) {
          progress?.reporter.determinate('Movendo reclassificados', current, total);
        },
      );
    }

    final summary = ReevaluateSummary(
      total: results.length,
      recategorized: toMove.length,
      unchanged: unchanged,
    );
    return (results, summary);
  }
}
