import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';

String extensionOf(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz')) {
    return 'tar.gz';
  }
  if (lower.endsWith('.sql.gz')) {
    return 'sql.gz';
  }
  if (lower.endsWith('.pindex.tmp')) {
    return 'pindex.tmp';
  }
  final extension = p.extension(lower);
  if (extension.isEmpty) {
    return '';
  }
  return extension.substring(1);
}

class DirectoryScanner {
  DirectoryScanner(this.config);

  final OrganizerConfig config;

  Future<List<FileEntry>> scan(
    Directory root, {
    void Function()? onFile,
  }) async {
    final normalizedRoot = Directory(p.normalize(root.absolute.path));
    final exists = await normalizedRoot.exists();
    if (!exists) {
      throw FileSystemException(
        'Pasta nao encontrada',
        normalizedRoot.path,
      );
    }

    final entries = <FileEntry>[];
    await for (final entity in normalizedRoot.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File && entity is! Directory) {
        continue;
      }

      final relativePath = p.relative(entity.path, from: normalizedRoot.path);
      if (_isInsideManagedDirectory(relativePath)) {
        continue;
      }

      final stat = await entity.stat();
      final basename = p.basename(entity.path);
      entries.add(FileEntry(
        entity: entity,
        type: entity is Directory ? EntryType.directory : EntryType.file,
        root: normalizedRoot,
        relativePath: relativePath,
        name: basename,
        extension: entity is Directory ? '' : extensionOf(basename),
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
      ));
      onFile?.call();
    }

    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return entries;
  }

  bool _isInsideManagedDirectory(String relativePath) {
    final parts = p.split(relativePath);
    return parts.isNotEmpty &&
        (parts.first == config.quarantineDirectoryName ||
            parts.first == config.autoOrganizedDirectoryName ||
            parts.first == 'debug');
  }

}
