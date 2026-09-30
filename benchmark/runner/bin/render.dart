import 'dart:convert';
import 'dart:io';

import 'package:fast_xlsx_benchmark_runner/report.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: dart run bin/render.dart RESULTS.json');
  }
  final input = File(args.single);
  final payload = Map<String, dynamic>.from(
    jsonDecode(await input.readAsString()) as Map,
  );
  final output = File(input.path.replaceFirst(RegExp(r'\.json$'), '.md'));
  await output.writeAsString(renderReport(payload));
  stdout.writeln('Wrote ${output.path}');
}
