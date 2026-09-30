import 'dart:convert';
import 'dart:io';

import '../../common/workload.dart';
import 'fixture.dart';
import 'package:fast_xlsx_benchmark_runner/report.dart';

typedef BenchCase = ({String name, int rows, int columns});

const libraries = ['fast_xlsx', 'excel_plus', 'excel_community'];
const versions = {
  'fast_xlsx': 'local 0.1.0',
  'excel_plus': '2.23.0',
  'excel_community': '2.4.1',
};
const standardCases = <BenchCase>[
  (name: '10k', rows: 1000, columns: 10),
  (name: '100k', rows: 10000, columns: 10),
  (name: '1m_tall', rows: 100000, columns: 10),
  (name: '1m_wide', rows: 20000, columns: 50),
];
const stressCase = (name: '5m_tall', rows: 500000, columns: 10);

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final benchmarkRoot = File.fromUri(Platform.script).parent.parent.parent;
  final dart = Platform.environment['DART_BIN'] ?? Platform.resolvedExecutable;
  final runner = _Runner(benchmarkRoot, dart);
  if (!options.skipSetup) await runner.setup();
  final workdir = await Directory.systemTemp.createTemp('fast_xlsx_benchmark_');
  try {
    final warmup = File('${workdir.path}/warmup.xlsx');
    final warmupChecksum = await generateFixture(warmup, 16, 10);
    final profileWarmups = <String, File>{};
    for (final profile in representativeProfiles) {
      final file = File('${workdir.path}/warmup_$profile.xlsx');
      final summary = await generateProfileFixture(file, 16, 10, profile);
      if (summary != expectedProfile(profile, 16, 10)) {
        throw StateError('Incorrect $profile warmup fixture: $summary');
      }
      profileWarmups[profile] = file;
    }
    await runner.smoke(workdir, warmup, warmupChecksum, profileWarmups);
    if (options.smoke) return;

    final runCore = options.suite == 'all' || options.suite == 'core';
    final runParity = options.suite == 'all' || options.suite == 'parity';
    final runRepresentative =
        options.suite == 'all' || options.suite == 'representative';
    final available = [...standardCases, if (options.stress) stressCase];
    final selected = !runCore
        ? <BenchCase>[]
        : options.selectedCases.isEmpty
        ? available
        : [
            ...standardCases,
            stressCase,
          ].where((item) => options.selectedCases.contains(item.name)).toList();
    final results = <Map<String, dynamic>>[];
    final extras = <Map<String, dynamic>>[];
    final parityResults = <Map<String, dynamic>>[];
    final representativeResults = <Map<String, dynamic>>[];
    for (final item in selected) {
      stdout.writeln('Generating ${item.name} input...');
      final fixture = File('${workdir.path}/${item.name}.xlsx');
      final checksum = await generateFixture(fixture, item.rows, item.columns);
      for (final mode in ['write_path', 'read_path']) {
        for (
          var repetition = 0;
          repetition < options.repetitions;
          repetition++
        ) {
          final order = [
            ...libraries.skip(repetition % libraries.length),
            ...libraries.take(repetition % libraries.length),
          ];
          for (final library in order) {
            stdout.writeln(
              '${item.name} $mode $library ${repetition + 1}/${options.repetitions}',
            );
            final (result, output) = await runner.checkedRun(
              workdir,
              library,
              mode,
              item.rows,
              item.columns,
              fixture,
              warmup,
              checksum,
            );
            result.addAll({'case': item.name, 'repetition': repetition + 1});
            results.add(result);
            if (mode == 'write_path') {
              if (repetition == 0) {
                final verifier = library == 'fast_xlsx'
                    ? 'excel_plus'
                    : 'fast_xlsx';
                await runner.checkedRun(
                  workdir,
                  verifier,
                  'read_path',
                  item.rows,
                  item.columns,
                  output,
                  warmup,
                  checksum,
                );
              }
              await output.delete();
            }
          }
        }
      }
      if (item.name == '100k' || item.name == '1m_tall') {
        for (final mode in ['read_buffered', 'read_stream', 'write_stream']) {
          for (
            var repetition = 0;
            repetition < options.repetitions;
            repetition++
          ) {
            stdout.writeln(
              '${item.name} fast_xlsx $mode ${repetition + 1}/${options.repetitions}',
            );
            final (result, output) = await runner.checkedRun(
              workdir,
              'fast_xlsx',
              mode,
              item.rows,
              item.columns,
              fixture,
              warmup,
              checksum,
            );
            result.addAll({'case': item.name, 'repetition': repetition + 1});
            extras.add(result);
            if (mode == 'write_stream') await output.delete();
          }
        }
      }
      await fixture.delete();
    }

    if (runParity) {
      for (final item in <BenchCase>[
        (name: '500_text', rows: 10, columns: 50),
        (name: '1m_text', rows: 20000, columns: 50),
      ]) {
        stdout.writeln('Running competitor-style ${item.name} lifecycle...');
        final expected = expectedProfile(
          'shared_unique',
          item.rows,
          item.columns,
        );
        for (
          var repetition = 0;
          repetition < options.repetitions;
          repetition++
        ) {
          final order = [
            ...libraries.skip(repetition % libraries.length),
            ...libraries.take(repetition % libraries.length),
          ];
          for (final library in order) {
            stdout.writeln(
              '${item.name} parity $library ${repetition + 1}/${options.repetitions}',
            );
            final (result, output) = await runner.checkedRun(
              workdir,
              library,
              'parity',
              item.rows,
              item.columns,
              warmup,
              warmup,
              expected.checksum,
            );
            result.addAll({'case': item.name, 'repetition': repetition + 1});
            parityResults.add(result);
            final verifier = library == 'fast_xlsx'
                ? 'excel_plus'
                : 'fast_xlsx';
            await runner.checkedRun(
              workdir,
              verifier,
              'read_profile_shared_unique',
              item.rows,
              item.columns,
              output,
              profileWarmups['shared_unique']!,
              expected.checksum,
            );
            await output.delete();
          }
        }
      }
    }

    if (runRepresentative) {
      const rows = 100000;
      const columns = 10;
      for (final profile in representativeProfiles) {
        stdout.writeln('Generating $profile input...');
        final fixture = File('${workdir.path}/$profile.xlsx');
        final summary = await generateProfileFixture(
          fixture,
          rows,
          columns,
          profile,
        );
        if (summary != expectedProfile(profile, rows, columns)) {
          throw StateError('Incorrect $profile fixture: $summary');
        }
        for (
          var repetition = 0;
          repetition < options.repetitions;
          repetition++
        ) {
          final order = [
            ...libraries.skip(repetition % libraries.length),
            ...libraries.take(repetition % libraries.length),
          ];
          for (final library in order) {
            stdout.writeln(
              '$profile import $library ${repetition + 1}/${options.repetitions}',
            );
            final (result, _) = await runner.checkedRun(
              workdir,
              library,
              'read_profile_$profile',
              rows,
              columns,
              fixture,
              profileWarmups[profile]!,
              summary.checksum,
              expectedCells: summary.cells,
            );
            result.addAll({'profile': profile, 'repetition': repetition + 1});
            representativeResults.add(result);
          }
        }
        await fixture.delete();
      }
    }

    final dartVersion = await Process.run(dart, ['--version']);
    final machine = await Process.run('uname', ['-m']);
    final timestamp = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'timestamp_utc': timestamp.toIso8601String(),
      'platform': Platform.operatingSystemVersion,
      'architecture': (machine.stdout as String).trim(),
      'cpu_count': Platform.numberOfProcessors,
      'dart_version': '${dartVersion.stdout}${dartVersion.stderr}'.trim(),
      'packages': versions,
      'repetitions': options.repetitions,
      'suite': options.suite,
      'fixture':
          'single-sheet inline-string OOXML, integers/doubles/text/booleans, ZIP deflate 6',
      'monitor':
          'Dart isolate sampling process RSS and dedicated temporary directory every 10 ms',
      'cases': selected
          .map(
            (item) => {
              'name': item.name,
              'rows': item.rows,
              'columns': item.columns,
            },
          )
          .toList(),
      'results': results,
      'fast_xlsx_extras': extras,
      'parity_results': parityResults,
      'representative_results': representativeResults,
    };
    final outputDir =
        options.outputDir ?? Directory('${benchmarkRoot.path}/results');
    await outputDir.create(recursive: true);
    final stem =
        '${timestamp.year.toString().padLeft(4, '0')}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}';
    final jsonFile = File('${outputDir.path}/$stem.json');
    final reportFile = File('${outputDir.path}/$stem.md');
    await jsonFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
    await reportFile.writeAsString(renderReport(payload));
    stdout.writeln('Wrote ${jsonFile.path} and ${reportFile.path}');
  } finally {
    await workdir.delete(recursive: true);
  }
}

final class _Options {
  _Options(
    this.smoke,
    this.stress,
    this.skipSetup,
    this.repetitions,
    this.suite,
    this.selectedCases,
    this.outputDir,
  );

  final bool smoke;
  final bool stress;
  final bool skipSetup;
  final int repetitions;
  final String suite;
  final Set<String> selectedCases;
  final Directory? outputDir;

  static _Options parse(List<String> args) {
    var smoke = false;
    var stress = false;
    var skipSetup = false;
    var repetitions = 3;
    var suite = 'all';
    Directory? outputDir;
    final selected = <String>{};
    const names = {'10k', '100k', '1m_tall', '1m_wide', '5m_tall'};
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--smoke':
          smoke = true;
        case '--stress':
          stress = true;
        case '--skip-setup':
          skipSetup = true;
        case '--repetitions':
          if (++index >= args.length) {
            throw FormatException('Missing repetitions');
          }
          repetitions = int.parse(args[index]);
        case '--case':
          if (++index >= args.length || !names.contains(args[index])) {
            throw FormatException(
              'Expected --case followed by a case name: $names',
            );
          }
          selected.add(args[index]);
        case '--suite':
          if (++index >= args.length ||
              !{
                'all',
                'core',
                'parity',
                'representative',
              }.contains(args[index])) {
            throw FormatException(
              'Expected --suite all|core|parity|representative',
            );
          }
          suite = args[index];
        case '--output-dir':
          if (++index >= args.length) {
            throw FormatException('Missing output directory');
          }
          outputDir = Directory(args[index]);
        default:
          throw FormatException('Unknown argument: ${args[index]}');
      }
    }
    if (repetitions < 1) {
      throw FormatException('--repetitions must be positive');
    }
    if (selected.isNotEmpty && suite != 'all' && suite != 'core') {
      throw FormatException('--case only applies to the core suite');
    }
    return _Options(
      smoke,
      stress,
      skipSetup,
      repetitions,
      suite,
      selected,
      outputDir,
    );
  }
}

final class _Runner {
  _Runner(this.root, this.dart);
  final Directory root;
  final String dart;
  var _serial = 0;

  Future<void> setup() async {
    for (final library in libraries) {
      stdout.writeln('Resolving $library dependencies...');
      final result = await Process.run(
        dart,
        ['pub', 'get'],
        workingDirectory: '${root.path}/$library',
        environment: {'CI': 'true'},
      );
      if (result.exitCode != 0) {
        throw StateError(
          '$library pub get failed:\n${result.stdout}\n${result.stderr}',
        );
      }
    }
  }

  Future<void> smoke(
    Directory workdir,
    File warmup,
    int checksum,
    Map<String, File> profileWarmups,
  ) async {
    stdout.writeln('Smoke testing all readers, writers, and cross-reads...');
    for (final library in libraries) {
      await checkedRun(
        workdir,
        library,
        'read_path',
        16,
        10,
        warmup,
        warmup,
        checksum,
      );
    }
    for (final producer in libraries) {
      final (_, output) = await checkedRun(
        workdir,
        producer,
        'write_path',
        16,
        10,
        warmup,
        warmup,
        checksum,
      );
      for (final consumer in libraries) {
        await checkedRun(
          workdir,
          consumer,
          'read_path',
          16,
          10,
          output,
          warmup,
          checksum,
        );
      }
      await output.delete();
    }
    for (final mode in ['read_buffered', 'read_stream']) {
      await checkedRun(
        workdir,
        'fast_xlsx',
        mode,
        16,
        10,
        warmup,
        warmup,
        checksum,
      );
    }
    final (_, output) = await checkedRun(
      workdir,
      'fast_xlsx',
      'write_stream',
      16,
      10,
      warmup,
      warmup,
      checksum,
    );
    await output.delete();
    for (final profile in representativeProfiles) {
      final summary = expectedProfile(profile, 16, 10);
      for (final library in libraries) {
        await checkedRun(
          workdir,
          library,
          'read_profile_$profile',
          16,
          10,
          profileWarmups[profile]!,
          profileWarmups[profile]!,
          summary.checksum,
          expectedCells: summary.cells,
        );
      }
    }
    final textSummary = expectedProfile('shared_unique', 16, 10);
    for (final producer in libraries) {
      final (_, output) = await checkedRun(
        workdir,
        producer,
        'parity',
        16,
        10,
        warmup,
        warmup,
        textSummary.checksum,
      );
      for (final consumer in libraries) {
        await checkedRun(
          workdir,
          consumer,
          'read_profile_shared_unique',
          16,
          10,
          output,
          profileWarmups['shared_unique']!,
          textSummary.checksum,
        );
      }
      await output.delete();
    }
    stdout.writeln('Smoke checks passed.');
  }

  Future<(Map<String, dynamic>, File)> checkedRun(
    Directory workdir,
    String library,
    String mode,
    int rows,
    int columns,
    File fixture,
    File warmup,
    int expected, {
    int? expectedCells,
  }) async {
    final id = _serial++;
    final output = File('${workdir.path}/${library}_${mode}_$id.xlsx');
    final scratch = Directory('${workdir.path}/scratch_$id');
    await scratch.create();
    try {
      final process = await Process.run(
        dart,
        [
          'run',
          'bin/worker.dart',
          mode,
          '$rows',
          '$columns',
          fixture.path,
          output.path,
          warmup.path,
        ],
        workingDirectory: '${root.path}/$library',
        environment: {
          'TMPDIR': scratch.path,
          'TMP': scratch.path,
          'TEMP': scratch.path,
          'CI': 'true',
        },
      );
      if (process.exitCode != 0) {
        throw StateError(
          '$library $mode failed (${process.exitCode}):\n${process.stdout}\n${process.stderr}',
        );
      }
      final lines = (process.stdout as String).trim().split('\n');
      final jsonLine = lines.lastWhere(
        (line) => line.startsWith('{'),
        orElse: () => '',
      );
      if (jsonLine.isEmpty) {
        throw StateError('No result from $library $mode: ${process.stdout}');
      }
      final result = Map<String, dynamic>.from(jsonDecode(jsonLine) as Map);
      result.addAll({'library': library, 'mode': mode});
      if (result['rows'] != rows ||
          result['cells'] != (expectedCells ?? rows * columns) ||
          (mode == 'parity'
              ? result['first_cell'] != 'R0C0'
              : result['checksum'] != expected)) {
        throw StateError('Incorrect $library $mode result: $result');
      }
      return (result, output);
    } finally {
      await scratch.delete(recursive: true);
    }
  }
}
