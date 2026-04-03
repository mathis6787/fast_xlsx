import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rs/native_toolchain_rs.dart';

Future<void> runLocalBuild(BuildInput input, BuildOutputBuilder output) async {
  final rustBuilder = RustBuilder(
    assetName: 'src/fast_xlsx_bindings.g.dart',
    cratePath: 'rust',
    extraCargoEnvironmentVariables: {
      'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER': 'aarch64-linux-gnu-gcc',
    },
  );

  final logger = Logger.detached('RustBuilder')
    ..level = Level.INFO
    ..onRecord.listen((record) {
      final outputSink = record.level >= Level.WARNING ? stderr : stdout;
      outputSink.writeln(record.message);
      if (record.error != null) {
        outputSink.writeln(record.error);
      }
      if (record.stackTrace != null) {
        outputSink.writeln(record.stackTrace);
      }
    });

  await rustBuilder.run(input: input, output: output, logger: logger);
}
