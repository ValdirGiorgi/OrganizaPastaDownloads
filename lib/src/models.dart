import 'dart:io';

enum EntryType {
  file,
  directory,
}

enum FileAction {
  keep,
  review,
  quarantine,
}

enum RiskLevel {
  low,
  medium,
  high,
}

class FileEntry {
  FileEntry({
    required this.entity,
    required this.type,
    required this.root,
    required this.relativePath,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final FileSystemEntity entity;
  final EntryType type;
  final Directory root;
  final String relativePath;
  final String name;
  final String extension;
  final int sizeBytes;
  final DateTime modifiedAt;

  bool get isFile => type == EntryType.file;

  bool get isDirectory => type == EntryType.directory;

  File get file => File(entity.path);

  Directory get directory => Directory(entity.path);
}

class AnalysisResult {
  AnalysisResult({
    required this.entry,
    required this.action,
    required this.category,
    required this.risk,
    required this.reason,
    this.duplicateGroup,
    this.hash,
    this.origin,
  });

  final FileEntry entry;
  FileAction action;
  String category;
  RiskLevel risk;
  String reason;
  String? duplicateGroup;
  String? hash;

  /// Onde o item estava antes desta execucao (preenchido apenas na
  /// reavaliacao, indicando pasta gerenciada + categoria de origem).
  String? origin;
}

class ScanSummary {
  ScanSummary(this.results);

  final List<AnalysisResult> results;

  int get totalFiles => results.length;

  int get totalBytes =>
      results.fold<int>(0, (total, item) => total + item.entry.sizeBytes);

  Map<FileAction, int> get actionCounts {
    final counts = <FileAction, int>{};
    for (final result in results) {
      counts[result.action] = (counts[result.action] ?? 0) + 1;
    }
    return counts;
  }

  Map<FileAction, int> get actionBytes {
    final bytes = <FileAction, int>{};
    for (final result in results) {
      bytes[result.action] =
          (bytes[result.action] ?? 0) + result.entry.sizeBytes;
    }
    return bytes;
  }
}
