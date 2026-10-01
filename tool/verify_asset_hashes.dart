import 'dart:io';

import 'package:args/args.dart';
import 'package:fast_xlsx/src/hook/download_asset.dart';
import 'package:fast_xlsx/src/hook/hashes.dart';
import 'package:fast_xlsx/src/hook/targets.dart';
import 'package:fast_xlsx/src/hook/version.dart';

Future<void> main(List<String> args) async {
  final options = (ArgParser()..addOption('assets-dir')).parse(args);
  final assetsPath = options.option('assets-dir');
  final directory = assetsPath == null
      ? await Directory.systemTemp.createTemp('fast_xlsx_assets_')
      : Directory(assetsPath);
  try {
    validatePinnedTargets(assetHashes);
    if (assetsPath == null) {
      for (final target in supportedTargets) {
        await downloadAsset(
          targetOS: target.os,
          targetArchitecture: target.architecture,
          outputDirectory: directory,
        ).timeout(const Duration(minutes: 2));
      }
    }
    await verifyAssetsDirectory(directory);
    stdout.writeln(
      'Verified all ${supportedTargets.length} assets for $version.',
    );
  } finally {
    if (assetsPath == null) {
      await directory.delete(recursive: true);
    }
  }
}

void validatePinnedTargets(Map<String, String> hashes) {
  final names = {
    for (final target in supportedTargets)
      createAssetFileName(target.os, target.architecture),
  };
  final missing = names.difference(hashes.keys.toSet());
  final unexpected = hashes.keys.toSet().difference(names);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw StateError(
      'Pinned hashes do not match supported targets. '
      'Missing: $missing; unexpected: $unexpected',
    );
  }
}

Future<void> verifyAssetsDirectory(
  Directory directory, {
  Map<String, String> expectedHashes = assetHashes,
}) async {
  validatePinnedTargets(expectedHashes);
  for (final entry in expectedHashes.entries) {
    final file = File.fromUri(directory.absolute.uri.resolve(entry.key));
    if (!await file.exists()) {
      throw StateError('Missing release asset: ${entry.key}');
    }
    final actual = await hashAsset(file);
    if (actual != entry.value) {
      throw StateError(
        'Hash mismatch for ${entry.key}: $actual != ${entry.value}',
      );
    }
    stdout.writeln('Verified ${entry.key}');
  }
}
