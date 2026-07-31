import 'dart:io';

import 'package:organiza_downloads/src/ai_categories.dart';
import 'package:test/test.dart';

void main() {
  test('normaliza categorias por texto separado por ponto e virgula', () {
    final categories = AiCategoryParser.parseInline(
      'Faculdade; Trabalho Remoto; impostos; faculdade',
    );

    expect(
        categories,
        containsAll([
          'faculdade',
          'trabalho_remoto',
          'impostos',
          'outros',
        ]));
    expect(categories.where((item) => item == 'faculdade'), hasLength(1));
  });

  test('carrega categorias de json objeto', () async {
    final temp = await Directory.systemTemp.createTemp('ai_categories_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/categorias.json');
    await file.writeAsString('{"categories":["Casa","Trabalho","Fotos"]}');

    final categories = await AiCategoryParser.parseJsonFile(file.path);

    expect(categories, containsAll(['casa', 'trabalho', 'fotos', 'outros']));
  });

  test('carrega categorias de json array', () async {
    final temp = await Directory.systemTemp.createTemp('ai_categories_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/categorias.json');
    await file.writeAsString('["Casa","Trabalho"]');

    final categories = await AiCategoryParser.parseJsonFile(file.path);

    expect(categories, containsAll(['casa', 'trabalho', 'outros']));
  });

  test('rejeita menos de duas categorias validas', () {
    expect(
      () => AiCategoryParser.parseInline('Casa; ; @@@'),
      throwsFormatException,
    );
  });
}
