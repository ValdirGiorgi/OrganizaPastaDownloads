import 'dart:io';

import 'package:organiza_downloads/src/duplicates.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:test/test.dart';

void main() {
  test('confirma duplicatas por hash e manda copias para quarentena', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_test_');
    addTearDown(() => temp.delete(recursive: true));

    final first = File('${temp.path}/a.txt')..writeAsStringSync('igual');
    final second = File('${temp.path}/b.txt')..writeAsStringSync('igual');
    final results = [
      _result(temp, first, 'a.txt'),
      _result(temp, second, 'b.txt'),
    ];

    await DuplicateDetector().markDuplicates(
      results,
      hashDuplicates: true,
    );

    expect(results.first.action, FileAction.review);
    expect(results.last.action, FileAction.quarantine);
    expect(results.last.category, 'duplicados');
    expect(results.last.hash, isNotEmpty);
  });

  test('hash confirmado vence classificacao keep da IA', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_test_');
    addTearDown(() => temp.delete(recursive: true));

    final first = File('${temp.path}/documento.pdf')
      ..writeAsStringSync('igual');
    final second = File('${temp.path}/documento (1).pdf')
      ..writeAsStringSync('igual');
    final results = [
      _result(temp, first, 'documento.pdf', action: FileAction.keep),
      _result(temp, second, 'documento (1).pdf', action: FileAction.keep),
    ];

    await DuplicateDetector().markDuplicates(
      results,
      hashDuplicates: true,
    );

    expect(results.first.action, FileAction.keep);
    expect(results.last.action, FileAction.quarantine);
    expect(results.last.category, 'duplicados');
    expect(results.last.reason, contains('duplicata confirmada por hash'));
    expect(results.last.reason, contains('classificacao anterior: keep'));
  });

  test('marca pasta com sufixo de copia como duplicata provavel', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_test_');
    addTearDown(() => temp.delete(recursive: true));

    final original = Directory('${temp.path}/documentos')..createSync();
    final copy = Directory('${temp.path}/documentos (1)')..createSync();
    final results = [
      _directoryResult(temp, original, 'documentos'),
      _directoryResult(temp, copy, 'documentos (1)'),
    ];

    await DuplicateDetector().markDuplicates(
      results,
      hashDuplicates: true,
    );

    expect(results.first.action, FileAction.review);
    expect(results.last.action, FileAction.quarantine);
    expect(results.last.category, 'duplicados');
    expect(results.last.duplicateGroup, startsWith('name-dup-'));
    expect(results.last.reason, contains('duplicata provavel pelo nome'));
  });
}

AnalysisResult _result(
  Directory root,
  File file,
  String relativePath, {
  FileAction action = FileAction.review,
}) {
  return AnalysisResult(
    entry: FileEntry(
      entity: file,
      type: EntryType.file,
      root: root,
      relativePath: relativePath,
      name: relativePath,
      extension: 'txt',
      sizeBytes: file.lengthSync(),
      modifiedAt: file.lastModifiedSync(),
    ),
    action: action,
    category: 'documentos',
    risk: RiskLevel.medium,
    reason: 'teste',
  );
}

AnalysisResult _directoryResult(
  Directory root,
  Directory directory,
  String relativePath,
) {
  return AnalysisResult(
    entry: FileEntry(
      entity: directory,
      type: EntryType.directory,
      root: root,
      relativePath: relativePath,
      name: relativePath,
      extension: '',
      sizeBytes: 0,
      modifiedAt: directory.statSync().modified,
    ),
    action: FileAction.review,
    category: 'documentos',
    risk: RiskLevel.medium,
    reason: 'teste',
  );
}
