import 'dart:math';

const _libraries = ['fast_xlsx', 'excel_plus', 'excel_community'];

String renderReport(Map<String, dynamic> payload) {
  final records = (payload['results'] as List).cast<Map<String, dynamic>>();
  final cases = (payload['cases'] as List).cast<Map<String, dynamic>>();
  final lines = <String>[
    '# XLSX benchmark results',
    '',
    'Run: ${payload['timestamp_utc']}',
    '',
    'Host: ${payload['platform']} (${payload['architecture']}), '
        '${payload['cpu_count']} logical CPUs; Dart: ${payload['dart_version']}',
    'Packages: fast_xlsx local 0.1.0, excel_plus 2.23.0, excel_community 2.4.1',
    '',
    'The runner, fixtures, and memory monitor are implemented in Dart. '
        'fast_xlsx uses a local Rust build selected by hooks.user_defines.',
    '',
    '${payload['repetitions']} fresh processes per case, each with a 16 × 10 warmup. '
        'Times exclude process startup and build hooks. '
        'Peak process RSS and dedicated temporary-directory bytes are sampled '
        'every 10 ms by a second Dart isolate. RSS is absolute process memory, '
        'not memory added by the operation.',
    'Full-import cases traverse every cell and pass row, cell, and checksum '
        'validation. Each library’s first core export per size is '
        'independently cross-read.',
    '',
  ];
  for (final item in cases) {
    final name = item['name'] as String;
    final rows = item['rows'] as int;
    final columns = item['columns'] as int;
    lines.addAll([
      '## $name ($rows × $columns cells)',
      '',
      '| Operation | Library | Median total (s) | Range (s) | Phase 1 (s) | Phase 2 (s) | Cells/s | Peak RSS (MiB) | Sampled temp (MiB) | XLSX (MiB) |',
      '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|',
    ]);
    for (final mode in ['write_path', 'read_path']) {
      for (final library in _libraries) {
        final group = records
            .where(
              (record) =>
                  record['case'] == name &&
                  record['mode'] == mode &&
                  record['library'] == library,
            )
            .toList();
        if (group.isEmpty) continue;
        final total = _median(group, 'total_us') / 1e6;
        final first =
            _median(group, mode == 'write_path' ? 'create_us' : 'open_us') /
            1e6;
        final second =
            _median(group, mode == 'write_path' ? 'output_us' : 'iterate_us') /
            1e6;
        final values = group.map(
          (record) => (record['total_us'] as num).toDouble() / 1e6,
        );
        final low = values.reduce(min);
        final high = values.reduce(max);
        final rss = _median(group, 'peak_rss_bytes') / 1048576;
        final temp = _median(group, 'peak_temp_bytes') / 1048576;
        final size = _median(group, 'file_bytes') / 1048576;
        final operation = mode == 'write_path' ? 'Export' : 'Import';
        lines.add(
          '| $operation | $library | ${_fixed(total, 3)} | '
          '${_fixed(low, 3)}–${_fixed(high, 3)} | ${_fixed(first, 3)} | '
          '${_fixed(second, 3)} | ${(rows * columns / total).round()} | '
          '${_fixed(rss, 1)} | ${_fixed(temp, 1)} | ${_fixed(size, 2)} |',
        );
      }
    }
    lines.add('');
  }
  if (cases.isNotEmpty) {
    lines.add(
      'Phase 1/2 mean create/output for export and open/full traversal '
      'for import. The range is minimum–maximum of the measured repetitions.',
    );
  }
  lines.addAll([
    'A sampled temp value of zero means no bytes were observed at 10 ms '
        'intervals; it does not prove there was no temporary disk I/O. '
        'Results are specific to this hardware, fixtures, and adapters.',
    'Timings vary by hardware and system load. Run all three libraries on '
        'the same machine, back to back, for a fair comparison.',
    '',
  ]);
  final extras = (payload['fast_xlsx_extras'] as List)
      .cast<Map<String, dynamic>>();
  if (extras.isNotEmpty) {
    lines.addAll([
      '## fast_xlsx API variants',
      '',
      '| Case | Mode | Median total (s) | Range (s) | Peak RSS (MiB) | Sampled temp (MiB) |',
      '|---|---|---:|---:|---:|---:|',
    ]);
    for (final name in ['100k', '1m_tall']) {
      for (final mode in ['read_buffered', 'read_stream', 'write_stream']) {
        final group = extras
            .where((record) => record['case'] == name && record['mode'] == mode)
            .toList();
        if (group.isEmpty) continue;
        final times = group.map(
          (record) => (record['total_us'] as num).toDouble() / 1e6,
        );
        lines.add(
          '| $name | $mode | ${_fixed(_median(group, 'total_us') / 1e6, 3)} | '
          '${_fixed(times.reduce(min), 3)}–${_fixed(times.reduce(max), 3)} | '
          '${_fixed(_median(group, 'peak_rss_bytes') / 1048576, 1)} | '
          '${_fixed(_median(group, 'peak_temp_bytes') / 1048576, 1)} |',
        );
      }
    }
    lines.add('');
  }
  final parity = ((payload['parity_results'] ?? <dynamic>[]) as List)
      .cast<Map<String, dynamic>>();
  if (parity.isNotEmpty) {
    lines.addAll([
      '## Competitor-style all-text lifecycle',
      '',
      'Every cell contains `R{row}C{column}`. Create and encode-to-bytes '
          'follow the competitors’ all-text workload; the final phase opens '
          'the generated bytes and accesses A1. It is intentionally a '
          'first-cell measurement, not a full import. A1 access may trigger '
          'different amounts of parsing in each library. Each generated file '
          'is fully cross-read by another library outside the timed phases.',
      '',
      '| Cells | Library | Create (s) | Encode bytes (s) | Open + A1 (s) | Total (s) | Range (s) | Peak RSS (MiB) | Sampled temp (MiB) | XLSX (MiB) |',
      '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|',
    ]);
    for (final caseName in ['500_text', '1m_text']) {
      for (final library in _libraries) {
        final group = parity
            .where(
              (record) =>
                  record['case'] == caseName && record['library'] == library,
            )
            .toList();
        if (group.isEmpty) continue;
        final times = group.map(
          (record) => (record['total_us'] as num).toDouble() / 1e6,
        );
        lines.add(
          '| ${caseName == '500_text' ? 500 : 1000000} | $library | '
          '${_fixed(_median(group, 'create_us') / 1e6, 3)} | '
          '${_fixed(_median(group, 'output_us') / 1e6, 3)} | '
          '${_fixed(_median(group, 'open_us') / 1e6, 3)} | '
          '${_fixed(_median(group, 'total_us') / 1e6, 3)} | '
          '${_fixed(times.reduce(min), 3)}–${_fixed(times.reduce(max), 3)} | '
          '${_fixed(_median(group, 'peak_rss_bytes') / 1048576, 1)} | '
          '${_fixed(_median(group, 'peak_temp_bytes') / 1048576, 1)} | '
          '${_fixed(_median(group, 'file_bytes') / 1048576, 2)} |',
        );
      }
    }
    lines.add('');
    lines.add(
      'This lifecycle excludes the final file write and complete '
      'worksheet traversal from its timed phases. Use the core and '
      'representative tables for complete-file performance.',
    );
    lines.add('');
  }
  final representative =
      ((payload['representative_results'] ?? <dynamic>[]) as List)
          .cast<Map<String, dynamic>>();
  if (representative.isNotEmpty) {
    lines.addAll([
      '## Representative input variants',
      '',
      'Each input is a neutral 100,000 × 10 XLSX generated before timing. '
          'Every reader opens the same file, traverses all rows, and validates '
          'the nonempty cell count and position-sensitive value checksum. '
          '`sparse_mixed` omits 20% of cells.',
      '',
      '| Input | Library | Full import (s) | Range (s) | Peak RSS (MiB) | Sampled temp (MiB) | XLSX (MiB) |',
      '|---|---|---:|---:|---:|---:|---:|',
    ]);
    for (final profile in [
      'inline_repeated',
      'shared_repeated',
      'inline_unique',
      'shared_unique',
      'sparse_mixed',
    ]) {
      for (final library in _libraries) {
        final group = representative
            .where(
              (record) =>
                  record['profile'] == profile && record['library'] == library,
            )
            .toList();
        if (group.isEmpty) continue;
        final times = group.map(
          (record) => (record['total_us'] as num).toDouble() / 1e6,
        );
        lines.add(
          '| $profile | $library | '
          '${_fixed(_median(group, 'total_us') / 1e6, 3)} | '
          '${_fixed(times.reduce(min), 3)}–${_fixed(times.reduce(max), 3)} | '
          '${_fixed(_median(group, 'peak_rss_bytes') / 1048576, 1)} | '
          '${_fixed(_median(group, 'peak_temp_bytes') / 1048576, 1)} | '
          '${_fixed(_median(group, 'file_bytes') / 1048576, 2)} |',
        );
      }
    }
    lines.add('');
  }
  final large = cases
      .where(
        (item) => (item['rows'] as int) * (item['columns'] as int) >= 1000000,
      )
      .toList();
  if (large.isNotEmpty) {
    final writeGains = <double>[];
    final readGains = <double>[];
    final memoryRatios = <double>[];
    for (final item in large) {
      for (final mode in ['write_path', 'read_path']) {
        double metric(String library, String key) => _median(
          records
              .where(
                (record) =>
                    record['case'] == item['name'] &&
                    record['mode'] == mode &&
                    record['library'] == library,
              )
              .toList(),
          key,
        );
        final fastTime = metric('fast_xlsx', 'total_us');
        final peerTime = min(
          metric('excel_plus', 'total_us'),
          metric('excel_community', 'total_us'),
        );
        final fastRss = metric('fast_xlsx', 'peak_rss_bytes');
        final peerRss = min(
          metric('excel_plus', 'peak_rss_bytes'),
          metric('excel_community', 'peak_rss_bytes'),
        );
        (mode == 'write_path' ? writeGains : readGains).add(
          peerTime / fastTime,
        );
        memoryRatios.add(peerRss / fastRss);
      }
    }
    lines.addAll([
      '## Interpretation',
      '',
      'Across the million-cell shapes, fast_xlsx exported '
          '${_multiples(writeGains)} '
          'faster and fully imported '
          '${_multiples(readGains)} '
          'faster than the fastest peer in each case. The peer with the lowest '
          'peak RSS in each case used '
          '${_multiples(memoryRatios)} '
          'the process memory of fast_xlsx.',
      '',
    ]);
    final bigParity = parity
        .where((record) => record['case'] == '1m_text')
        .toList();
    if (bigParity.isNotEmpty) {
      double phase(String library, String key) =>
          _median(
            bigParity.where((record) => record['library'] == library).toList(),
            key,
          ) /
          1e6;
      final fastCreate = phase('fast_xlsx', 'create_us');
      final peerCreate = min(
        phase('excel_plus', 'create_us'),
        phase('excel_community', 'create_us'),
      );
      if (fastCreate > peerCreate) {
        lines.add(
          'In the all-text 1M-cell byte lifecycle, fast_xlsx created '
          'the cells in ${_fixed(fastCreate, 3)} s versus '
          '${_fixed(peerCreate, 3)} s for the fastest peer. Its shorter '
          'overall time came from encoding and A1 access, not faster '
          'cell construction.',
        );
        lines.add('');
      }
      double size(String library) =>
          _median(
            bigParity.where((record) => record['library'] == library).toList(),
            'file_bytes',
          ) /
          1048576;
      lines.add(
        'The all-text XLSX output was '
        '${_fixed(size('fast_xlsx'), 2)} MiB for fast_xlsx and '
        '${_fixed(size('excel_plus'), 2)} MiB for excel_plus. Encoding time '
        'therefore includes each library’s file representation and '
        'compression choices.',
      );
      lines.add('');
    }
    final small = cases.where((item) => item['name'] == '10k');
    if (small.isNotEmpty) {
      double time(String library, String mode) =>
          _median(
            records
                .where(
                  (record) =>
                      record['case'] == '10k' &&
                      record['mode'] == mode &&
                      record['library'] == library,
                )
                .toList(),
            'total_us',
          ) /
          1e6;
      lines.add(
        'At 10k cells, fast_xlsx took '
        '${_fixed(time('fast_xlsx', 'write_path'), 3)} s to export and '
        '${_fixed(time('fast_xlsx', 'read_path'), 3)} s to import. The '
        'fastest peer took '
        '${_fixed(min(time('excel_plus', 'write_path'), time('excel_community', 'write_path')), 3)} s '
        'and ${_fixed(min(time('excel_plus', 'read_path'), time('excel_community', 'read_path')), 3)} s.',
      );
      lines.add('');
    }
    final tallVariants = extras
        .where((record) => record['case'] == '1m_tall')
        .toList();
    if (tallVariants.isNotEmpty) {
      double variant(String mode, String key) =>
          _median(
            tallVariants.where((record) => record['mode'] == mode).toList(),
            key,
          ) /
          1048576;
      lines.add(
        'For the 1M-cell tall case, fast_xlsx stream read and write '
        'sampled ${_fixed(variant('read_stream', 'peak_temp_bytes'), 1)} and '
        '${_fixed(variant('write_stream', 'peak_temp_bytes'), 1)} MiB of temporary '
        'disk use. Buffered read sampled '
        '${_fixed(variant('read_buffered', 'peak_rss_bytes'), 1)} MiB peak RSS, '
        'versus ${_fixed(variant('read_stream', 'peak_rss_bytes'), 1)} MiB '
        'for stream read.',
      );
      lines.add('');
    }
    final representativeGains = <double>[];
    if (representative.isNotEmpty) {
      for (final profile in [
        'inline_repeated',
        'shared_repeated',
        'inline_unique',
        'shared_unique',
        'sparse_mixed',
      ]) {
        double medianFor(String library) => _median(
          representative
              .where(
                (record) =>
                    record['profile'] == profile &&
                    record['library'] == library,
              )
              .toList(),
          'total_us',
        );
        representativeGains.add(
          min(medianFor('excel_plus'), medianFor('excel_community')) /
              medianFor('fast_xlsx'),
        );
      }
      lines.add(
        'Across the representative 1M-cell inputs, the fastest peer’s '
        'full-import time divided by fast_xlsx’s was '
        '${_multiples(representativeGains)}. '
        'A value above 1 means fast_xlsx was faster.',
      );
      lines.add('');
    }
    if ([...writeGains, ...readGains].every((gain) => gain > 1) &&
        memoryRatios.every((ratio) => ratio > 1) &&
        representativeGains.every((gain) => gain > 1)) {
      lines.add(
        'Recommendation: continue developing fast_xlsx for backend, '
        'single-sheet, large-file workflows. Complete-file measurements show '
        'a consistent speed and memory advantage. Validate against user '
        'files and deployment environments before making broader claims.',
      );
    } else {
      lines.add(
        'Recommendation: review the per-operation tradeoffs before '
        'investing further. These measurements do not show a consistent '
        'speed and memory advantage across the large-file cases.',
      );
    }
    lines.add('');
  }
  return '${lines.join('\n')}\n';
}

double _median(List<Map<String, dynamic>> records, String key) {
  final values =
      records.map((record) => (record[key] as num).toDouble()).toList()..sort();
  if (values.isEmpty) throw StateError('Missing measurements for $key');
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

String _fixed(double value, int digits) => value.toStringAsFixed(digits);

String _multiples(List<double> values) {
  final low = _fixed(values.reduce(min), 1);
  final high = _fixed(values.reduce(max), 1);
  return low == high ? '$low×' : '$low–$high×';
}
