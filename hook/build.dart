import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rs/native_toolchain_rs.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final builder = RustBuilder(
      assetName: 'src/fast_xlsx_bindings.g.dart',
      cratePath: 'rust',
    );

    try {
      await builder.run(input: input, output: output);
    } on ProcessException catch (error) {
      stderr.writeln(error.message);
      rethrow;
    }
  });
}
