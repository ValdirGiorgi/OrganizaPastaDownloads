import 'dart:io';

class RunLogger {
  RunLogger._(this._sink, this.path);

  final IOSink? _sink;
  final String? path;

  static Future<RunLogger> create(File logFile) async {
    await logFile.parent.create(recursive: true);
    return RunLogger._(
      logFile.openWrite(mode: FileMode.append),
      logFile.path,
    );
  }

  void writeln([String text = '']) {
    stdout.writeln(text);
    _sink?.writeln(text);
  }

  /// Grava apenas no arquivo, sem duplicar no terminal (usado quando o
  /// texto ja foi impresso no terminal por outro caminho, ex.: progress bar).
  void fileOnly(String text) {
    _sink?.writeln(text);
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
