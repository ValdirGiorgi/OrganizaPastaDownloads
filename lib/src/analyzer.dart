import 'dart:io';

import 'package:organiza_downloads/src/ai_classifier.dart';
import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/duplicates.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:organiza_downloads/src/progress.dart';
import 'package:organiza_downloads/src/rules.dart';
import 'package:organiza_downloads/src/scanner.dart';

class Analyzer {
  Analyzer(this.config);

  final OrganizerConfig config;

  Future<List<AnalysisResult>> analyze(
    Directory root, {
    required bool hashDuplicates,
    AiClassifierOptions? aiOptions,
    ProgressSink? progress,
    void Function(AiCallStats stats)? onAiCall,
    Future<void> Function(int count)? onScanned,
  }) async {
    final entries = await DirectoryScanner(config).scan(
      root,
      onFile: progress == null ? null : progress.scanningFile,
    );
    if (entries.isEmpty) {
      return const [];
    }
    await onScanned?.call(entries.length);

    final classifier = RuleClassifier(config);
    final results = <AnalysisResult>[];
    for (final entry in entries) {
      results.add(classifier.classify(entry));
      progress?.classifyingFile(entries.length);
    }
    if (aiOptions != null) {
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
    final hashCandidateCount = _hashCandidateCount(results);
    await DuplicateDetector().markDuplicates(
      results,
      hashDuplicates: hashDuplicates,
      onHashFile: progress == null
          ? null
          : () => progress.hashingFile(hashCandidateCount),
    );
    return results;
  }

  int _hashCandidateCount(List<AnalysisResult> results) {
    final counts = <int, int>{};
    for (final result in results) {
      if (!result.entry.isFile) {
        continue;
      }
      counts[result.entry.sizeBytes] =
          (counts[result.entry.sizeBytes] ?? 0) + 1;
    }
    var total = 0;
    for (final result in results) {
      if (!result.entry.isFile) {
        continue;
      }
      if ((counts[result.entry.sizeBytes] ?? 0) > 1) {
        total++;
      }
    }
    return total;
  }
}
