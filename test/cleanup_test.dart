import 'dart:io';

import 'package:organiza_downloads/src/cleanup.dart';
import 'package:organiza_downloads/src/config.dart';
import 'package:test/test.dart';

void main() {
  test('limpa pastas vazias sem tocar nas saidas gerenciadas', () async {
    final temp = await Directory.systemTemp.createTemp('organiza_cleanup_');
    addTearDown(() => temp.delete(recursive: true));

    final empty = Directory('${temp.path}/antiga/sub');
    await empty.create(recursive: true);
    final managed = Directory('${temp.path}/_auto_organizado/documentos');
    await managed.create(recursive: true);

    final removed = await EmptyDirectoryCleaner(OrganizerConfig.defaults()).clean(
      temp,
    );

    expect(removed, 2);
    expect(await Directory('${temp.path}/antiga').exists(), isFalse);
    expect(await managed.exists(), isTrue);
  });
}
