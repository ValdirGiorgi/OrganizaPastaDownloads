import 'dart:io';
import 'dart:math' as math;

class ProgressReporter {
  ProgressReporter({
    IOSink? output,
    bool? enabled,
  })  : _output = output ?? stdout,
        _enabled = enabled ?? stdout.hasTerminal;

  final IOSink _output;
  final bool _enabled;
  final _watch = Stopwatch()..start();
  final _frames = const ['|', '/', '-', r'\'];
  String _lastLine = '';
  int _frameIndex = 0;

  void indeterminate(String label, int count) {
    if (!_enabled) {
      if (count == 0 || count % 250 == 0) {
        _output.writeln('$label: $count');
      }
      return;
    }
    if (!_shouldRender()) {
      return;
    }
    final frame = _nextFrame();
    _render('$frame $label ${_dots(count)} $count arquivos');
  }

  void determinate(String label, int current, int total) {
    if (total <= 0) {
      indeterminate(label, current);
      return;
    }

    if (!_enabled) {
      if (current == total || current == 0 || current % 250 == 0) {
        _output.writeln('$label: $current/$total');
      }
      return;
    }
    if (current < total && !_shouldRender()) {
      return;
    }

    final percent = (current / total).clamp(0, 1).toDouble();
    final width = 26;
    final filled = math.max(0, math.min(width, (percent * width).floor()));
    final bar = StringBuffer();
    for (var index = 0; index < width; index++) {
      if (index < filled) {
        bar.write('=');
      } else if (index == filled && current < total) {
        bar.write('>');
      } else {
        bar.write('.');
      }
    }

    final frame = current >= total ? 'OK' : _nextFrame();
    final percentText = (percent * 100).toStringAsFixed(0).padLeft(3);
    _render('$frame [$bar] $percentText% $label ($current/$total)');
  }

  void message(String text) {
    if (_enabled && _lastLine.isNotEmpty) {
      _output.writeln();
      _lastLine = '';
    }
    _output.writeln(text);
  }

  void done(String text) {
    if (_enabled) {
      _render('OK $text');
      _output.writeln();
      _lastLine = '';
    } else {
      _output.writeln(text);
    }
  }

  bool _shouldRender() {
    return _watch.elapsedMilliseconds >= 80;
  }

  String _nextFrame() {
    _watch.reset();
    final frame = _frames[_frameIndex % _frames.length];
    _frameIndex++;
    return frame;
  }

  String _dots(int count) {
    final dots = (count ~/ 20) % 4;
    return List.filled(dots, '.').join();
  }

  void _render(String line) {
    final padded = line.padRight(_lastLine.length);
    _output.write('\r$padded');
    _lastLine = line;
  }
}

class ProgressSink {
  ProgressSink(this.reporter);

  final ProgressReporter reporter;
  int scannedFiles = 0;
  int classifiedFiles = 0;
  int hashedFiles = 0;

  void scanningFile() {
    scannedFiles++;
    reporter.indeterminate('Varrendo pastas', scannedFiles);
  }

  void classifyingFile(int total) {
    classifiedFiles++;
    reporter.determinate('Classificando bagunca', classifiedFiles, total);
  }

  void hashingFile(int total) {
    hashedFiles++;
    reporter.determinate('Comparando duplicatas', hashedFiles, total);
  }
}
