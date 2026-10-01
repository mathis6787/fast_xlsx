import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  await FfiGenerator(
    input: Input(entryPoints: [packageRoot.resolve('src/fast_xlsx.h')]),
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/src/fast_xlsx_bindings.g.dart'),
      ),
      style: const NativeExternalBindings(
        assetId: 'package:fast_xlsx/src/fast_xlsx_bindings.g.dart',
      ),
      commentType: const CommentType.none(),
    ),
    visitors: [
      Visitor(
        func: (node) {
          node.isIncluded = node.originalName.startsWith('fx_');
        },
        struct: (node) {
          node.isIncluded = node.originalName.startsWith('Fx');
        },
        enumClass: (node) {
          node.isIncluded = node.originalName.startsWith('Fx');
          node.silenceWarning = true;
        },
        typealias: (node) {
          node.isIncluded = node.originalName.startsWith('Fx')
              ? TypealiasInclude.ifUsed
              : TypealiasInclude.never;
        },
      ),
    ],
  ).generate();
}
