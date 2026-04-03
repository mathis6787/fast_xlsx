import 'dart:io';

import 'package:args/args.dart';
import 'package:code_assets/code_assets.dart';
import 'package:fast_xlsx/src/hook/local_build.dart';
import 'package:fast_xlsx/src/hook/targets.dart';
import 'package:hooks/hooks.dart';

const _macOSTargetVersion = 13;

void main(List<String> args) async {
  final (os: os, architecture: architecture) = parseArguments(args);
  final input = createBuildInput(os, architecture);
  final output = BuildOutputBuilder();
  await runLocalBuild(input, output);
}

({String architecture, String os}) parseArguments(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'architecture',
      abbr: 'a',
      allowed: [Architecture.arm64.name, Architecture.x64.name],
      mandatory: true,
    )
    ..addOption(
      'os',
      abbr: 'o',
      allowed: [OS.linux.name, OS.macOS.name, OS.windows.name],
      mandatory: true,
    );
  final argResults = parser.parse(args);

  final os = argResults.option('os');
  final architecture = argResults.option('architecture');
  if (os == null || architecture == null) {
    stdout.writeln(parser.usage);
    exit(1);
  }

  return (os: os, architecture: architecture);
}

BuildInput createBuildInput(String osString, String architectureString) {
  final packageRoot = Platform.script.resolve('..');
  final outputDirectoryShared = packageRoot.resolve(
    '.dart_tool/fast_xlsx/shared/',
  );
  final outputFile = packageRoot.resolve('.dart_tool/fast_xlsx/output.json');

  final os = OS.fromString(osString);
  final architecture = Architecture.fromString(architectureString);
  if (!isSupportedTarget(os, architecture)) {
    throw UnsupportedError(
      'Unsupported target: ${os.name} ${architecture.name}',
    );
  }

  final inputBuilder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot,
      packageName: 'fast_xlsx',
      outputDirectoryShared: outputDirectoryShared,
      outputFile: outputFile,
    )
    ..config.setupBuild(linkingEnabled: false)
    ..addExtension(
      CodeAssetExtension(
        targetArchitecture: architecture,
        targetOS: os,
        linkModePreference: LinkModePreference.dynamic,
        macOS: os == OS.macOS
            ? MacOSCodeConfig(targetVersion: _macOSTargetVersion)
            : null,
      ),
    );

  return inputBuilder.build();
}
