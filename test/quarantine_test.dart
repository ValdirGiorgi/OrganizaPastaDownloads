import 'dart:io';

import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';
import 'package:organiza_downloads/src/quarantine.dart';
import 'package:test/test.dart';

void main() {
  test('modo real cria as pastas de saida antes de mover', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_outputs_');
    addTearDown(() => temp.delete(recursive: true));

    final missing = File('${temp.path}/sumiu.pdf');
    final result = AnalysisResult(
      entry: FileEntry(
        entity: missing,
        type: EntryType.file,
        root: temp,
        relativePath: 'sumiu.pdf',
        name: 'sumiu.pdf',
        extension: 'pdf',
        sizeBytes: 0,
        modifiedAt: DateTime(2026),
      ),
      action: FileAction.keep,
      category: 'documentos',
      risk: RiskLevel.high,
      reason: 'teste',
    );

    final summary = await QuarantineMover(OrganizerConfig.defaults()).moveAll([
      result,
    ]);

    expect(summary.totalMoved, 0);
    expect(
      await Directory('${temp.path}/_organiza_quarentena').exists(),
      isTrue,
    );
    expect(
      await Directory('${temp.path}/_auto_organizado/documentos').exists(),
      isTrue,
    );
  });

  test('modo real cria pastas de saida mesmo sem arquivos', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_empty_');
    addTearDown(() => temp.delete(recursive: true));

    final summary = await QuarantineMover(OrganizerConfig.defaults()).moveAll(
      const [],
      root: temp,
    );

    expect(summary.totalMoved, 0);
    expect(
      await Directory('${temp.path}/_organiza_quarentena').exists(),
      isTrue,
    );
    expect(
      await Directory('${temp.path}/_auto_organizado').exists(),
      isTrue,
    );
  });

  test('modo real cria saidas e move todos os arquivos', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_quarantine_');
    addTearDown(() => temp.delete(recursive: true));

    final installer = File('${temp.path}/setup.exe');
    await installer.writeAsString('instalador');
    final document = File('${temp.path}/recibo.pdf');
    await document.writeAsString('documento');

    final quarantineResult = AnalysisResult(
      entry: FileEntry(
        entity: installer,
        type: EntryType.file,
        root: temp,
        relativePath: 'setup.exe',
        name: 'setup.exe',
        extension: 'exe',
        sizeBytes: await installer.length(),
        modifiedAt: await installer.lastModified(),
      ),
      action: FileAction.quarantine,
      category: 'instaladores',
      risk: RiskLevel.medium,
      reason: 'teste',
    );
    final keepResult = AnalysisResult(
      entry: FileEntry(
        entity: document,
        type: EntryType.file,
        root: temp,
        relativePath: 'recibo.pdf',
        name: 'recibo.pdf',
        extension: 'pdf',
        sizeBytes: await document.length(),
        modifiedAt: await document.lastModified(),
      ),
      action: FileAction.keep,
      category: 'financeiro_fiscal',
      risk: RiskLevel.high,
      reason: 'teste',
    );

    final summary = await QuarantineMover(OrganizerConfig.defaults()).moveAll([
      quarantineResult,
      keepResult,
    ]);

    expect(summary.quarantined, 1);
    expect(summary.organized, 1);
    expect(await installer.exists(), isFalse);
    expect(await document.exists(), isFalse);
    expect(
      await File('${temp.path}/_organiza_quarentena/instaladores/setup.exe')
          .exists(),
      isTrue,
    );
    expect(
      await File(
        '${temp.path}/_auto_organizado/financeiro_fiscal/recibo.pdf',
      ).exists(),
      isTrue,
    );
  });

  test('modo real move pasta inteira mantendo conteudo interno', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_dir_move_');
    addTearDown(() => temp.delete(recursive: true));

    final folder = Directory('${temp.path}/Fotos antigas');
    await folder.create();
    final inner = File('${folder.path}/foto.jpg');
    await inner.writeAsString('imagem');

    final result = AnalysisResult(
      entry: FileEntry(
        entity: folder,
        type: EntryType.directory,
        root: temp,
        relativePath: 'Fotos antigas',
        name: 'Fotos antigas',
        extension: '',
        sizeBytes: 0,
        modifiedAt: (await folder.stat()).modified,
      ),
      action: FileAction.review,
      category: 'imagens',
      risk: RiskLevel.medium,
      reason: 'teste',
    );

    final summary = await QuarantineMover(OrganizerConfig.defaults()).moveAll([
      result,
    ]);

    expect(summary.organized, 1);
    expect(await folder.exists(), isFalse);
    expect(
      await File(
        '${temp.path}/_auto_organizado/imagens/Fotos antigas/foto.jpg',
      ).exists(),
      isTrue,
    );
  });
}
