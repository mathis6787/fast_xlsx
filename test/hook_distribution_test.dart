import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:fast_xlsx/src/hook/download_asset.dart';
import 'package:fast_xlsx/src/hook/targets.dart';
import 'package:fast_xlsx/src/hook/version.dart';
import 'package:test/test.dart';

void main() {
  group('distribution hook helpers', () {
    test('supported targets match the backend matrix', () {
      expect(supportedTargets, const [
        (os: OS.linux, architecture: Architecture.arm64),
        (os: OS.linux, architecture: Architecture.x64),
        (os: OS.macOS, architecture: Architecture.arm64),
        (os: OS.macOS, architecture: Architecture.x64),
        (os: OS.windows, architecture: Architecture.arm64),
        (os: OS.windows, architecture: Architecture.x64),
      ]);
    });

    test('asset filenames are stable and platform specific', () {
      expect(
        createAssetFileName(OS.linux, Architecture.x64),
        'libfast_xlsx_linux_x86_64.so',
      );
      expect(
        createAssetFileName(OS.macOS, Architecture.arm64),
        'libfast_xlsx_macos_arm64.dylib',
      );
      expect(
        createAssetFileName(OS.windows, Architecture.arm64),
        'fast_xlsx_windows_arm64.dll',
      );
    });

    test('download uri targets the configured GitHub release', () {
      expect(
        downloadUri('libfast_xlsx_linux_x86_64.so'),
        Uri.parse(
          'https://github.com/mathis6787/fast_xlsx/releases/download/'
          '$version/libfast_xlsx_linux_x86_64.so',
        ),
      );
    });

    test('hashAsset computes md5 deterministically', () async {
      final tempDir = await Directory.systemTemp.createTemp('fast_xlsx_hash_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/sample.bin');
      await file.writeAsString('abc');

      expect(await hashAsset(file), '900150983cd24fb0d6963f7d28e17f72');
    });

    test('unsupported targets throw a clear error', () {
      expect(
        () => getNameForTarget(OS.android, Architecture.arm64),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('Unsupported target'),
          ),
        ),
      );
    });
  });
}
