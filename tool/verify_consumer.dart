import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fast_xlsx/src/hook/hashes.dart';

import 'verify_asset_hashes.dart' show validatePinnedTargets;

Future<void> main(List<String> args) async {
  final options = (ArgParser()..addOption('target')).parse(args);
  final actualTarget = Abi.current().toString();
  final expectedTarget = options.option('target');
  if (expectedTarget != null && actualTarget != expectedTarget) {
    throw StateError('Expected $expectedTarget Dart SDK, got $actualTarget.');
  }
  // Empty pins would let the hook fall back to compiling Rust locally.
  validatePinnedTargets(assetHashes);
  final repository = Directory.fromUri(Platform.script.resolve('../'));
  final consumer = await Directory.systemTemp.createTemp('fast_xlsx_consumer_');
  try {
    await File.fromUri(consumer.uri.resolve('pubspec.yaml')).writeAsString('''
name: fast_xlsx_release_consumer
publish_to: none
environment:
  sdk: ^3.11.0
dependencies:
  fast_xlsx:
    path: ${jsonEncode(repository.path)}
dev_dependencies:
  test: ^1.25.6
hooks:
  user_defines:
    fast_xlsx:
      local_build: false
''');
    final tests = Directory.fromUri(consumer.uri.resolve('test/'));
    await tests.create();
    await File.fromUri(
      repository.uri.resolve('test/fast_xlsx_test.dart'),
    ).copy(File.fromUri(tests.uri.resolve('fast_xlsx_test.dart')).path);

    // Do not inherit the environment override that enables local Rust builds.
    final environment = Map<String, String>.from(Platform.environment)
      ..remove('FAST_XLSX_LOCAL_BUILD');
    stdout.writeln('Testing released native asset on $actualTarget.');
    for (final command in [
      ['pub', 'get'],
      ['test', '--reporter=expanded'],
    ]) {
      final process = await Process.start(
        Platform.resolvedExecutable,
        command,
        workingDirectory: consumer.path,
        environment: environment,
        includeParentEnvironment: false,
        mode: ProcessStartMode.inheritStdio,
      );
      final result = await process.exitCode;
      if (result != 0) {
        exitCode = result;
        return;
      }
    }
    stdout.writeln(
      'Released native asset consumer tests passed on $actualTarget.',
    );
  } finally {
    await consumer.delete(recursive: true);
  }
}
