import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';

class CsvReportWriter {
  Future<void> write(
    File output,
    List<AnalysisResult> results, {
    required OrganizerConfig config,
    required String operation,
  }) async {
    await output.parent.create(recursive: true);
    final sink = output.openWrite();
    sink.writeln([
      'operacao',
      'origem',
      'destino',
      'action',
      'category',
      'risk',
      'reason',
      'path',
      'size_bytes',
      'modified_at',
      'duplicate_group',
      'hash',
    ].map(_escape).join(','));

    for (final result in results) {
      final destino = p.join(
        result.action == FileAction.quarantine
            ? config.quarantineDirectoryName
            : config.autoOrganizedDirectoryName,
        result.category,
      );
      sink.writeln([
        operation,
        result.origin ?? '',
        destino,
        result.action.name,
        result.category,
        result.risk.name,
        result.reason,
        result.entry.relativePath,
        result.entry.sizeBytes.toString(),
        result.entry.modifiedAt.toIso8601String(),
        result.duplicateGroup ?? '',
        result.hash ?? '',
      ].map(_escape).join(','));
    }
    await sink.flush();
    await sink.close();
  }

  String _escape(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }
}
