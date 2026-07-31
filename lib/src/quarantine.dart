import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:organiza_downloads/src/config.dart';
import 'package:organiza_downloads/src/models.dart';

class QuarantineMover {
  QuarantineMover(this.config);

  final OrganizerConfig config;

  Future<MoveSummary> moveAll(
    List<AnalysisResult> results, {
    Directory? root,
    void Function(int moved, int total)? onMove,
  }) async {
    await prepareOutputDirectories(results, root: root);

    var quarantined = 0;
    var organized = 0;
    var moved = 0;
    final total = results.length;

    for (final result in results) {
      final source = result.entry.entity;
      if (!await source.exists()) {
        continue;
      }

      final target = await _nextAvailableTarget(result);
      await target.parent.create(recursive: true);
      await _moveEntity(result.entry, target.path);
      moved++;
      if (result.action == FileAction.quarantine) {
        quarantined++;
      } else {
        organized++;
      }
      onMove?.call(moved, total);
    }
    return MoveSummary(
      organized: organized,
      quarantined: quarantined,
      skipped: total - moved,
    );
  }

  Future<void> prepareOutputDirectories(
    List<AnalysisResult> results, {
    Directory? root,
  }) async {
    final rootPath = _rootPath(results, root: root);
    if (rootPath == null) {
      return;
    }

    await Directory(p.join(rootPath, config.quarantineDirectoryName)).create(
      recursive: true,
    );
    await Directory(p.join(rootPath, config.autoOrganizedDirectoryName)).create(
      recursive: true,
    );

    final quarantineCategories = <String>{};
    final organizedCategories = <String>{};
    for (final result in results) {
      if (result.action == FileAction.quarantine) {
        quarantineCategories.add(result.category);
      } else {
        organizedCategories.add(result.category);
      }
    }

    for (final category in quarantineCategories) {
      await Directory(
        p.join(rootPath, config.quarantineDirectoryName, category),
      ).create(recursive: true);
    }
    for (final category in organizedCategories) {
      await Directory(
        p.join(rootPath, config.autoOrganizedDirectoryName, category),
      ).create(recursive: true);
    }
  }

  Future<int> move(
    List<AnalysisResult> results, {
    Directory? root,
    void Function(int moved, int total)? onMove,
  }) async {
    final summary = await moveAll(
      results
          .where((result) => result.action == FileAction.quarantine)
          .toList(),
      root: root,
      onMove: onMove,
    );
    return summary.quarantined;
  }

  Future<File> _nextAvailableTarget(AnalysisResult result) async {
    final root = result.entry.root.path;
    final outputDirectory = result.action == FileAction.quarantine
        ? config.quarantineDirectoryName
        : config.autoOrganizedDirectoryName;
    final baseTargetPath = p.join(
      root,
      outputDirectory,
      result.category,
      result.entry.relativePath,
    );

    var candidate = File(baseTargetPath);
    if (!await candidate.exists()) {
      return candidate;
    }

    final directory = p.dirname(baseTargetPath);
    final basename = p.basenameWithoutExtension(baseTargetPath);
    final extension = p.extension(baseTargetPath);
    var counter = 1;
    while (true) {
      candidate = File(p.join(directory, '$basename-$counter$extension'));
      if (!await candidate.exists()) {
        return candidate;
      }
      counter++;
    }
  }

  Future<void> _moveEntity(FileEntry entry, String targetPath) async {
    try {
      if (entry.isDirectory) {
        await entry.directory.rename(targetPath);
      } else {
        await entry.file.rename(targetPath);
      }
    } on FileSystemException {
      if (entry.isDirectory) {
        await _copyDirectory(entry.directory, Directory(targetPath));
        await entry.directory.delete(recursive: true);
      } else {
        await entry.file.copy(targetPath);
        await entry.file.delete();
      }
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final targetPath = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  String? _rootPath(List<AnalysisResult> results, {Directory? root}) {
    if (root != null) {
      return root.path;
    }
    if (results.isEmpty) {
      return null;
    }
    return results.first.entry.root.path;
  }
}

class MoveSummary {
  MoveSummary({
    required this.organized,
    required this.quarantined,
    required this.skipped,
  });

  final int organized;
  final int quarantined;
  final int skipped;

  int get totalMoved => organized + quarantined;
}
