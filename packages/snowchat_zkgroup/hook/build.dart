/// @file        build.dart
/// @description Build hook: compiles the first-party Rust crate
///              (native/snowchat_zkgroup) for the target the Dart / Flutter
///              tool asks for and reports the resulting dynamic library as a
///              code asset. Uses only the official `hooks` and `code_assets`
///              packages — no third-party Rust build helper sits in the build
///              path of crypto code.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-12
/// @lastUpdated 2026-11-12 (moved from the PoC to the product package; crate path)
///
/// @functions
///  - main(args): hook entry point (`build`).
///  - rustTarget(code): Rust target triple for an OS / architecture / SDK.
///  - targetEnvironment(code, triple): linker and deployment-target variables.
///  - rustFlags(code, crate, targetDir, home): path remapping + Android SONAME.
///  - findTool(name, extraDirs): absolute path of a build tool, fail-loud.
///  - crateInputs(crate): files whose change must re-run the hook.
///
/// @notes
///  - Android links with the NDK clang wrapper for `targetNdkApi` (the app's
///    minSdk), so the library cannot bind to symbols newer than the oldest
///    supported device.
///  - cargo is the rustup proxy run from the crate directory, so the pinned
///    `rust-toolchain.toml` (channel + mobile targets) is what builds.
///  - `--locked`: the build fails instead of silently resolving a dependency
///    version that is not in Cargo.lock.
///  - Requires on the build machine: rustup, protoc (a libsignal build script
///    compiles protobuf definitions). A missing tool stops the build with a
///    message that names it.
///  - Every target is always built from source, so no platform slice can be
///    missing from a release.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Crate location relative to this package's root.
const _cratePath = '../../native/snowchat_zkgroup/';

/// `[lib] name` of the crate — the stem of the produced library file.
const _libName = 'snowchat_zkgroup';

/// Asset name. `package:snowchat_zkgroup/src/bindings.dart` is the URI of the
/// library holding the `@Native` declarations, which is the default asset id
/// those declarations resolve against.
const _assetName = 'src/bindings.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    if (code.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError(
        'snowchat_zkgroup is built as a dynamic library only; '
        'static linking was requested.',
      );
    }

    final triple = rustTarget(code);
    final crate = Directory.fromUri(input.packageRoot.resolve(_cratePath));
    if (!File.fromUri(crate.uri.resolve('Cargo.toml')).existsSync()) {
      throw StateError('Rust crate not found at ${crate.path}');
    }
    // Shared across hook invocations so every target reuses one cargo cache
    // (registry build artifacts for host build scripts, incremental state).
    final targetDir = Directory.fromUri(
      input.outputDirectoryShared.resolve('cargo-target/'),
    );

    final home = Platform.environment['HOME'];
    final cargo = findTool('cargo', [if (home != null) '$home/.cargo/bin']);
    final protoc = findTool('protoc', ['/opt/homebrew/bin', '/usr/local/bin']);

    final stopwatch = Stopwatch()..start();
    final result = await Process.run(
      cargo,
      [
        'rustc',
        '--release',
        '--locked',
        '--lib',
        '--crate-type',
        'cdylib',
        '--target',
        triple,
        '--target-dir',
        targetDir.path,
      ],
      workingDirectory: crate.path,
      environment: {
        'PROTOC': protoc,
        'CARGO_ENCODED_RUSTFLAGS': rustFlags(
          code,
          crate: crate,
          targetDir: targetDir,
          home: home,
        ).join('\x1f'),
        ...targetEnvironment(code, triple),
      },
    );
    stopwatch.stop();
    if (result.exitCode != 0) {
      throw ProcessException(
        cargo,
        ['rustc', '--target', triple],
        'cargo failed (exit ${result.exitCode}).\n'
        '--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}',
        result.exitCode,
      );
    }
    stdout.writeln(
      'snowchat_zkgroup: built $triple in ${stopwatch.elapsedMilliseconds} ms',
    );

    final library = File.fromUri(
      targetDir.uri.resolve(
        '$triple/release/${code.targetOS.dylibFileName(_libName)}',
      ),
    );
    if (!library.existsSync()) {
      throw StateError('cargo succeeded but ${library.path} is missing');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
    output.dependencies.addAll(crateInputs(crate));
  });
}

/// Rust target triple for the requested OS / architecture / Apple SDK.
String rustTarget(CodeConfig code) {
  final os = code.targetOS;
  final arch = code.targetArchitecture;
  if (os == OS.android) {
    if (arch == Architecture.arm64) return 'aarch64-linux-android';
    if (arch == Architecture.arm) return 'armv7-linux-androideabi';
    if (arch == Architecture.x64) return 'x86_64-linux-android';
  } else if (os == OS.iOS) {
    final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    if (arch == Architecture.arm64) {
      return simulator ? 'aarch64-apple-ios-sim' : 'aarch64-apple-ios';
    }
    if (arch == Architecture.x64 && simulator) return 'x86_64-apple-ios';
  } else if (os == OS.macOS) {
    // Host target: used by `dart test` for this package only.
    if (arch == Architecture.arm64) return 'aarch64-apple-darwin';
    if (arch == Architecture.x64) return 'x86_64-apple-darwin';
  }
  throw UnsupportedError('snowchat_zkgroup: unsupported target $os / $arch');
}

/// Environment variables that select the linker and the minimum OS version
/// for [triple].
Map<String, String> targetEnvironment(CodeConfig code, String triple) {
  final os = code.targetOS;
  if (os == OS.iOS) {
    return {'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}.0'};
  }
  if (os == OS.macOS) {
    return {'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}.0'};
  }
  if (os == OS.android) {
    final compiler = code.cCompiler;
    if (compiler == null) {
      throw StateError('No NDK compiler was provided for $triple');
    }
    // The NDK ships one clang wrapper per (triple, API level). Its triple
    // spelling differs from Rust's for 32-bit ARM.
    final ndkTriple = triple == 'armv7-linux-androideabi'
        ? 'armv7a-linux-androideabi'
        : triple;
    final api = code.android.targetNdkApi;
    final binDir = File.fromUri(compiler.compiler).parent;
    final clang = File('${binDir.path}/$ndkTriple$api-clang');
    if (!clang.existsSync()) {
      throw StateError(
        'NDK compiler wrapper ${clang.path} not found (NDK API level $api).',
      );
    }
    final envTriple = triple.replaceAll('-', '_');
    return {
      'CARGO_TARGET_${envTriple.toUpperCase()}_LINKER': clang.path,
      'CC_$envTriple': clang.path,
      'AR_$envTriple': File.fromUri(compiler.archiver).path,
    };
  }
  return const {};
}

/// rustc flags for the target build (cargo applies them to the target only,
/// not to host build scripts, because `--target` is always passed).
///
/// Path remapping keeps the build machine's directories out of the shipped
/// binary: without it every panic location embeds an absolute path such as
/// `<home>/.cargo/git/checkouts/...`, which leaks the developer's account
/// name and makes the output differ between machines.
List<String> rustFlags(
  CodeConfig code, {
  required Directory crate,
  required Directory targetDir,
  required String? home,
}) {
  String trimmed(Directory dir) => dir.path.endsWith('/')
      ? dir.path.substring(0, dir.path.length - 1)
      : dir.path;
  final cargoHome =
      Platform.environment['CARGO_HOME'] ??
      (home != null ? '$home/.cargo' : null);
  return [
    if (cargoHome != null) '--remap-path-prefix=$cargoHome=/cargo',
    '--remap-path-prefix=${trimmed(crate.absolute)}=/snowchat_zkgroup',
    '--remap-path-prefix=${trimmed(targetDir.absolute)}=/target',
    // rustc sets no DT_SONAME on its own; give the library a proper one.
    if (code.targetOS == OS.android) ...[
      '-C',
      'link-arg=-Wl,-soname,${OS.android.dylibFileName(_libName)}',
    ],
  ];
}

/// Absolute path of [name], searched in [extraDirs] first and then in PATH.
/// IDE-launched builds (Xcode, Android Studio) often run with a PATH that
/// lacks the user's shell additions, hence the explicit directories.
String findTool(String name, List<String> extraDirs) {
  final pathDirs = (Platform.environment['PATH'] ?? '').split(':');
  for (final dir in [...extraDirs, ...pathDirs]) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir/$name');
    if (candidate.existsSync()) return candidate.path;
  }
  throw StateError(
    'Build tool "$name" not found (looked in $extraDirs and PATH). '
    'snowchat_zkgroup is built from source and needs rustup and protoc '
    'on the build machine.',
  );
}

/// Every file of the crate that decides the build output. The libsignal
/// crates are pinned by git revision in Cargo.lock, so they cannot change
/// without one of these files changing.
List<Uri> crateInputs(Directory crate) {
  final inputs = <Uri>[
    crate.uri.resolve('Cargo.toml'),
    crate.uri.resolve('Cargo.lock'),
    crate.uri.resolve('rust-toolchain.toml'),
  ];
  final sources = Directory.fromUri(crate.uri.resolve('src/'));
  for (final entity in sources.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.rs')) inputs.add(entity.uri);
  }
  return inputs;
}
