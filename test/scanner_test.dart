import 'dart:io';

import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:organiza_downloads/src/scanner.dart';
import 'package:test/test.dart';

void main() {
  test('scanner analisa somente itens diretos do diretorio', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_scan_');
    addTearDown(() => temp.delete(recursive: true));

    final directFile = File('${temp.path}/direto.pdf');
    await directFile.writeAsString('pdf');
    final directFolder = Directory('${temp.path}/Pasta direta');
    await directFolder.create();
    await File('${directFolder.path}/interno.pdf').writeAsString('interno');
    await Directory('${temp.path}/_auto_organizado').create();
    await Directory('${temp.path}/debug').create();

    final entries =
        await DirectoryScanner(OrganizerConfig.defaults()).scan(temp);

    expect(
        entries.map((entry) => entry.name),
        containsAll([
          'direto.pdf',
          'Pasta direta',
        ]));
    expect(entries.map((entry) => entry.name), isNot(contains('interno.pdf')));
    expect(entries.map((entry) => entry.name), isNot(contains('debug')));
    expect(
      entries.firstWhere((entry) => entry.name == 'Pasta direta').type,
      EntryType.directory,
    );
  });
}
