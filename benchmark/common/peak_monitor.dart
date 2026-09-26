import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

/// Samples the whole worker process, including native allocations, on a
/// separate isolate so synchronous XLSX work cannot block the sampler.
final class PeakMonitor {
  PeakMonitor._(this._port, this._isolate, this._control, this._peak);

  final ReceivePort _port;
  final Isolate _isolate;
  final SendPort _control;
  final Future<(int rssBytes, int tempBytes)> _peak;

  static Future<Map<String, Object>> measure(
    Future<Map<String, Object>> Function() work,
  ) async {
    final monitor = await start();
    late final Map<String, Object> result;
    late final (int rssBytes, int tempBytes) peak;
    try {
      result = await work();
    } finally {
      peak = await monitor.stop();
    }
    final endRss = ProcessInfo.currentRss;
    result.addAll({
      'rss_end_bytes': endRss,
      'peak_rss_bytes': max(peak.$1, endRss),
      'peak_temp_bytes': peak.$2,
      'sample_interval_ms': 10,
    });
    return result;
  }

  static Future<PeakMonitor> start() async {
    final port = ReceivePort();
    final ready = Completer<SendPort>();
    final peak = Completer<(int, int)>();
    port.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is (int, int)) {
        peak.complete(message);
      }
    });
    final isolate = await Isolate.spawn(_sample, (
      port.sendPort,
      Directory.systemTemp.path,
    ));
    return PeakMonitor._(port, isolate, await ready.future, peak.future);
  }

  Future<(int rssBytes, int tempBytes)> stop() async {
    _control.send(null);
    final result = await _peak;
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
    return result;
  }
}

void _sample((SendPort, String) input) {
  final commands = ReceivePort();
  input.$1.send(commands.sendPort);
  final tempDirectory = Directory(input.$2);
  var peakRss = 0;
  var peakTemp = 0;

  void sample() {
    peakRss = max(peakRss, ProcessInfo.currentRss);
    peakTemp = max(peakTemp, _directoryBytes(tempDirectory));
  }

  sample();
  final timer = Timer.periodic(
    const Duration(milliseconds: 10),
    (_) => sample(),
  );
  commands.listen((_) {
    timer.cancel();
    sample();
    input.$1.send((peakRss, peakTemp));
    commands.close();
  });
}

int _directoryBytes(Directory directory) {
  var total = 0;
  try {
    for (final entry in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is File) {
        try {
          total += entry.lengthSync();
        } on FileSystemException {
          // A temporary file may disappear between listing and stat.
        }
      }
    }
  } on FileSystemException {
    // The parent can clean up the directory after the measured operation.
  }
  return total;
}
