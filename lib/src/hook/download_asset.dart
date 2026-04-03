import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:fast_xlsx/src/hook/targets.dart';
import 'package:fast_xlsx/src/hook/version.dart';

const _repository = 'mathis6787/fast_xlsx';

Uri downloadUri(String assetFileName) => Uri.parse(
  'https://github.com/$_repository/releases/download/$version/$assetFileName',
);

Future<File> downloadAsset({
  required OS targetOS,
  required Architecture targetArchitecture,
  required Directory outputDirectory,
}) async {
  final assetFileName = createAssetFileName(targetOS, targetArchitecture);
  final uri = downloadUri(assetFileName);
  final request = await HttpClient().getUrl(uri);
  final response = await request.close();

  if (response.statusCode != HttpStatus.ok) {
    throw StateError(
      'Failed to download $assetFileName from $uri '
      '(HTTP ${response.statusCode}).',
    );
  }

  final libraryFile = File.fromUri(outputDirectory.uri.resolve(assetFileName));
  await libraryFile.create(recursive: true);
  await response.pipe(libraryFile.openWrite());
  return libraryFile;
}

Future<String> hashAsset(File assetFile) async {
  final fileHash = md5.convert(await assetFile.readAsBytes()).toString();
  return fileHash;
}
