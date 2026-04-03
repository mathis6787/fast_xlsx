import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:fast_xlsx/src/hook/download_asset.dart';
import 'package:fast_xlsx/src/hook/hashes.dart';
import 'package:fast_xlsx/src/hook/local_build.dart';
import 'package:fast_xlsx/src/hook/targets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final localBuild =
        (input.userDefines['local_build'] as bool? ?? false) ||
        _environmentFlagEnabled('FAST_XLSX_LOCAL_BUILD');
    final CodeConfig codeConfig;

    try {
      codeConfig = input.config.code;
    } catch (_) {
      return;
    }

    if (localBuild) {
      try {
        await runLocalBuild(input, output);
      } on ProcessException catch (error) {
        stderr.writeln(error.message);
        rethrow;
      }
      return;
    }

    if (assetHashes.isEmpty) {
      try {
        await runLocalBuild(input, output);
      } on ProcessException catch (error) {
        stderr.writeln(error.message);
        rethrow;
      }
      return;
    }

    final targetOS = codeConfig.targetOS;
    final targetArchitecture = codeConfig.targetArchitecture;
    final outputDirectory = Directory.fromUri(input.outputDirectory);
    final file = await downloadAsset(
      targetOS: targetOS,
      targetArchitecture: targetArchitecture,
      outputDirectory: outputDirectory,
    );

    await verifyAssetHash(
      file,
      targetOS: targetOS,
      targetArchitecture: targetArchitecture,
    );

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/fast_xlsx_bindings.g.dart',
        linkMode: DynamicLoadingBundled(),
        file: file.uri,
      ),
    );
  });
}

bool _environmentFlagEnabled(String name) {
  final value = Platform.environment[name]?.toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

Future<void> verifyAssetHash(
  File asset, {
  required OS targetOS,
  required Architecture targetArchitecture,
}) async {
  final assetFileName = createAssetFileName(targetOS, targetArchitecture);
  final expectedHash = assetHashes[assetFileName];
  if (expectedHash == null) {
    throw StateError(
      'Missing pinned hash for $assetFileName. '
      'Run `dart run tool/generate_asset_hashes.dart` after publishing assets.',
    );
  }

  final actualHash = await hashAsset(asset);
  if (actualHash != expectedHash) {
    throw StateError(
      'Asset hash mismatch for $assetFileName: $actualHash != $expectedHash',
    );
  }
}
