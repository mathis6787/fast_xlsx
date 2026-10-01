import 'dart:io';

import 'package:fast_xlsx/src/hook/targets.dart';
import 'package:test/test.dart';

import '../tool/verify_asset_hashes.dart';

void main() {
  late Directory directory;
  late Map<String, String> hashes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fast_xlsx_verify_test_');
    hashes = {
      for (final target in supportedTargets)
        createAssetFileName(target.os, target.architecture):
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    };
    for (final name in hashes.keys) {
      await File.fromUri(directory.uri.resolve(name)).writeAsString('abc');
    }
  });
  tearDown(() => directory.delete(recursive: true));

  test('verifies every supported asset without rewriting pins', () async {
    final original = Map<String, String>.from(hashes);
    await verifyAssetsDirectory(directory, expectedHashes: hashes);
    expect(hashes, original);
  });

  test('rejects a changed binary', () async {
    final name = hashes.keys.last;
    await File.fromUri(directory.uri.resolve(name)).writeAsString('changed');
    await expectLater(
      verifyAssetsDirectory(directory, expectedHashes: hashes),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Hash mismatch for $name'),
        ),
      ),
    );
  });

  test('rejects a missing binary', () async {
    final name = hashes.keys.last;
    await File.fromUri(directory.uri.resolve(name)).delete();
    await expectLater(
      verifyAssetsDirectory(directory, expectedHashes: hashes),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Missing release asset: $name'),
        ),
      ),
    );
  });

  test('rejects a missing pinned target', () {
    hashes.remove(hashes.keys.first);
    expect(() => validatePinnedTargets(hashes), throwsStateError);
  });

  test('rejects an unexpected pinned target', () {
    hashes['unexpected.dll'] = 'unused';
    expect(() => validatePinnedTargets(hashes), throwsStateError);
  });
}
