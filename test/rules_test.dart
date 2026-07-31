import 'dart:io';

import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:organiza_downloads/src/rules.dart';
import 'package:test/test.dart';

void main() {
  final config = OrganizerConfig.defaults();
  final classifier = RuleClassifier(config);
  final root = Directory.systemTemp;

  test('mantem documentos importantes por palavra-chave', () {
    final result = classifier.classify(_entry(
      root,
      'IRPF-A-2025-2024-DEC.pdf',
      extension: 'pdf',
    ));

    expect(result.action, FileAction.keep);
    expect(result.category, 'financeiro_fiscal');
    expect(result.risk, RiskLevel.high);
  });

  test('manda locks temporarios para quarentena', () {
    final result = classifier.classify(_entry(
      root,
      '.~lock.Curriculo.docx#',
      extension: 'docx#',
      size: 107,
    ));

    expect(result.action, FileAction.quarantine);
    expect(result.category, 'temporarios');
  });

  test('revisa modelos 3D em vez de apagar', () {
    final result = classifier.classify(_entry(
      root,
      'Clock.3mf',
      extension: '3mf',
      size: 4096,
    ));

    expect(result.action, FileAction.review);
    expect(result.category, 'modelos_3d');
  });

  test('instaladores vao para quarentena', () {
    final result = classifier.classify(_entry(
      root,
      'Firefox Installer.exe',
      extension: 'exe',
      size: 503848,
    ));

    expect(result.action, FileAction.quarantine);
    expect(result.category, 'instaladores');
  });

  test('pasta vazia nao vai automaticamente para quarentena', () {
    final result = classifier.classify(_entry(
      root,
      'Documentos Antigos',
      extension: '',
      size: 0,
      type: EntryType.directory,
    ));

    expect(result.action, FileAction.review);
    expect(result.category, 'outros');
  });
}

FileEntry _entry(
  Directory root,
  String name, {
  required String extension,
  int size = 123,
  EntryType type = EntryType.file,
}) {
  return FileEntry(
    entity: type == EntryType.directory ? Directory(name) : File(name),
    type: type,
    root: root,
    relativePath: name,
    name: name,
    extension: extension,
    sizeBytes: size,
    modifiedAt: DateTime(2026, 1, 1),
  );
}
