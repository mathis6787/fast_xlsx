import 'package:code_assets/code_assets.dart';

typedef SupportedTarget = ({OS os, Architecture architecture});

const supportedTargets = <SupportedTarget>[
  (os: OS.linux, architecture: Architecture.arm64),
  (os: OS.linux, architecture: Architecture.x64),
  (os: OS.macOS, architecture: Architecture.arm64),
  (os: OS.macOS, architecture: Architecture.x64),
  (os: OS.windows, architecture: Architecture.arm64),
  (os: OS.windows, architecture: Architecture.x64),
];

bool isSupportedTarget(OS os, Architecture architecture) =>
    supportedTargets.contains((os: os, architecture: architecture));

String getNameForTarget(OS os, Architecture architecture) {
  switch ((os, architecture)) {
    case (OS.linux, Architecture.arm64):
      return 'linux_aarch64';
    case (OS.linux, Architecture.x64):
      return 'linux_x86_64';
    case (OS.macOS, Architecture.arm64):
      return 'macos_arm64';
    case (OS.macOS, Architecture.x64):
      return 'macos_x86_64';
    case (OS.windows, Architecture.arm64):
      return 'windows_arm64';
    case (OS.windows, Architecture.x64):
      return 'windows_x86_64';
  }

  throw UnsupportedError('Unsupported target: ${os.name} ${architecture.name}');
}

String createTargetName(OS os, Architecture architecture) =>
    'fast_xlsx_${getNameForTarget(os, architecture)}';

String createAssetFileName(OS os, Architecture architecture) =>
    os.dylibFileName(createTargetName(os, architecture));
