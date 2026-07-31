import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:organiza_downloads/src/config.dart';

class EmptyDirectoryCleaner {
  EmptyDirectoryCleaner(this.config);

  final OrganizerConfig config;

  Future<int> clean(Directory root) async {
    final normalizedRoot = Directory(p.normalize(root.absolute.path));
    final directories = <Directory>[];

    await for (final entity in normalizedRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }

      final relativePath = p.relative(entity.path, from: normalizedRoot.path);
      if (_isManagedDirectory(relativePath)) {
        continue;
      }
      directories.add(entity);
    }

    directories.sort((a, b) {
      final aDepth = p.split(a.path).length;
      final bDepth = p.split(b.path).length;
      return bDepth.compareTo(aDepth);
    });

    var removed = 0;
    for (final directory in directories) {
      try {
        if (await _isEmpty(directory)) {
          await directory.delete();
          removed++;
        }
      } on FileSystemException {
        // If a directory cannot be read or removed, leave it in place.
      }
    }
    return removed;
  }

  bool _isManagedDirectory(String relativePath) {
    final parts = p.split(relativePath);
    return parts.isNotEmpty &&
        (parts.first == config.quarantineDirectoryName ||
            parts.first == config.autoOrganizedDirectoryName);
  }

  Future<bool> _isEmpty(Directory directory) async {
    await for (final _ in directory.list(followLinks: false)) {
      return false;
    }
    return true;
  }
}
