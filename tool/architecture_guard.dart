import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final invocation = _Invocation.parse(arguments);
  final repositoryRoot = await _gitRoot();
  final plan = await _MigrationPlan.load(repositoryRoot, invocation.planPath);

  switch (invocation.command) {
    case 'begin':
      final snapshot = await _RepositorySnapshot.capture(repositoryRoot);
      final output = _stateFile(repositoryRoot, plan.id);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      );
      stdout.writeln('Architecture baseline created: ${output.path}');
    case 'verify':
      final report = await _verify(
        repositoryRoot: repositoryRoot,
        plan: plan,
        skipCommands: invocation.skipCommands,
      );
      final reportFiles = await _writeReport(repositoryRoot, report);
      stdout.writeln('Architecture report: ${reportFiles.markdown.path}');
      stdout.writeln('Machine report: ${reportFiles.json.path}');
      if (!report.passed) {
        exitCode = 1;
      }
  }
}

Future<_GuardReport> _verify({
  required Directory repositoryRoot,
  required _MigrationPlan plan,
  required bool skipCommands,
}) async {
  final stateFile = _stateFile(repositoryRoot, plan.id);
  final after = await _RepositorySnapshot.capture(repositoryRoot);
  late final Set<String> changedPaths;

  if (await stateFile.exists()) {
    final decoded = jsonDecode(await stateFile.readAsString());
    final before = _RepositorySnapshot.fromJson(_objectMap(decoded));
    changedPaths = before.changedPaths(after);
  } else {
    changedPaths = await _changedSince(repositoryRoot, plan.baselineRef);
  }

  final unexpectedPaths =
      changedPaths.where((path) => !plan.allows(path)).toList(growable: false)
        ..sort();

  final responsibilityManifest = await _ResponsibilityManifest.load(
    repositoryRoot,
  );
  final responsibilities = responsibilityManifest.select(
    plan.protectedResponsibilityIds,
  );
  final missingProtectedFiles = <String>[];
  for (final responsibility in responsibilities) {
    for (final relativePath in responsibility.protectedFiles) {
      final file = File(_join(repositoryRoot.path, relativePath));
      if (!await file.exists()) {
        missingProtectedFiles.add(relativePath);
      }
    }
  }
  missingProtectedFiles.sort();

  final commands = <String>{
    ...plan.verificationCommands,
    for (final responsibility in responsibilities)
      ...responsibility.verificationCommands,
  }.toList(growable: false);
  final commandResults = skipCommands
      ? <_CommandResult>[]
      : await _runCommands(repositoryRoot, commands);

  return _GuardReport(
    planId: plan.id,
    description: plan.description,
    createdAt: DateTime.now().toUtc(),
    changedPaths: changedPaths.toList(growable: false)..sort(),
    unexpectedPaths: unexpectedPaths,
    missingProtectedFiles: missingProtectedFiles,
    protectedResponsibilities: responsibilities
        .map((item) => item.id)
        .toList(growable: false),
    commandResults: commandResults,
    commandsSkipped: skipCommands,
  );
}

Future<List<_CommandResult>> _runCommands(
  Directory repositoryRoot,
  List<String> commands,
) async {
  final results = <_CommandResult>[];
  for (final command in commands) {
    final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final arguments = Platform.isWindows
        ? <String>['/d', '/s', '/c', command]
        : <String>['-lc', command];
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: repositoryRoot.path,
      runInShell: false,
    );
    results.add(
      _CommandResult(
        command: command,
        exitCode: result.exitCode,
        standardOutput: result.stdout.toString(),
        standardError: result.stderr.toString(),
      ),
    );
  }
  return results;
}

Future<Set<String>> _changedSince(
  Directory repositoryRoot,
  String baselineRef,
) async {
  final tracked = await _git(repositoryRoot, <String>[
    'diff',
    '--name-only',
    '--diff-filter=ACDMRTUXB',
    baselineRef,
    '--',
  ]);
  final untracked = await _git(repositoryRoot, <String>[
    'ls-files',
    '--others',
    '--exclude-standard',
  ]);
  return <String>{..._nonEmptyLines(tracked), ..._nonEmptyLines(untracked)};
}

Future<Directory> _gitRoot() async {
  final result = await Process.run('git', <String>[
    'rev-parse',
    '--show-toplevel',
  ], runInShell: false);
  if (result.exitCode != 0) {
    throw StateError('Not inside a Git worktree: ${result.stderr}');
  }
  return Directory(result.stdout.toString().trim());
}

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout.toString();
}

List<String> _nonEmptyLines(String value) => value
    .split(RegExp(r'\r?\n'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

File _stateFile(Directory root, String planId) =>
    File(_join(root.path, '.architecture/state/$planId.before.json'));

Future<_ReportFiles> _writeReport(Directory root, _GuardReport report) async {
  final reports = Directory(_join(root.path, '.architecture/reports'));
  await reports.create(recursive: true);
  final stamp = report.createdAt.toIso8601String().replaceAll(':', '-');
  final baseName = '$stamp-${report.planId}';
  final jsonFile = File(_join(reports.path, '$baseName.json'));
  final markdownFile = File(_join(reports.path, '$baseName.md'));
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  await markdownFile.writeAsString(report.toMarkdown());
  return _ReportFiles(markdown: markdownFile, json: jsonFile);
}

String _join(String root, String relative) {
  final separator = Platform.pathSeparator;
  return '$root$separator${relative.replaceAll('/', separator)}';
}

Map<String, Object?> _objectMap(Object? value) =>
    (value! as Map<Object?, Object?>).map(
      (key, item) => MapEntry(key! as String, item),
    );

List<String> _stringList(Object? value) =>
    (value! as List<Object?>).map((item) => item! as String).toList();

class _Invocation {
  const _Invocation({
    required this.command,
    required this.planPath,
    required this.skipCommands,
  });

  final String command;
  final String planPath;
  final bool skipCommands;

  static _Invocation parse(List<String> arguments) {
    if (arguments.isEmpty ||
        (arguments.first != 'begin' && arguments.first != 'verify')) {
      throw ArgumentError(
        'Usage: dart run tool/architecture_guard.dart '
        '<begin|verify> --plan <file> [--skip-commands]',
      );
    }
    final planIndex = arguments.indexOf('--plan');
    if (planIndex < 0 || planIndex + 1 >= arguments.length) {
      throw ArgumentError('The --plan argument is required.');
    }
    return _Invocation(
      command: arguments.first,
      planPath: arguments[planIndex + 1],
      skipCommands: arguments.contains('--skip-commands'),
    );
  }
}

class _MigrationPlan {
  const _MigrationPlan({
    required this.id,
    required this.description,
    required this.baselineRef,
    required this.allowedPaths,
    required this.protectedResponsibilityIds,
    required this.verificationCommands,
  });

  final String id;
  final String description;
  final String baselineRef;
  final List<String> allowedPaths;
  final List<String> protectedResponsibilityIds;
  final List<String> verificationCommands;

  bool allows(String path) => allowedPaths.any(
    (allowed) =>
        allowed.endsWith('/') ? path.startsWith(allowed) : path == allowed,
  );

  static Future<_MigrationPlan> load(
    Directory root,
    String relativePath,
  ) async {
    final decoded = jsonDecode(
      await File(_join(root.path, relativePath)).readAsString(),
    );
    final json = _objectMap(decoded);
    return _MigrationPlan(
      id: json['id']! as String,
      description: json['description']! as String,
      baselineRef: json['baselineRef']! as String,
      allowedPaths: _stringList(json['allowedPaths']),
      protectedResponsibilityIds: _stringList(
        json['protectedResponsibilityIds'],
      ),
      verificationCommands: _stringList(json['verificationCommands']),
    );
  }
}

class _ResponsibilityManifest {
  const _ResponsibilityManifest(this.responsibilities);

  final List<_ProtectedResponsibility> responsibilities;

  List<_ProtectedResponsibility> select(List<String> ids) {
    final indexed = <String, _ProtectedResponsibility>{
      for (final item in responsibilities) item.id: item,
    };
    return ids
        .map((id) {
          final item = indexed[id];
          if (item == null) {
            throw StateError('Unknown protected responsibility: $id');
          }
          return item;
        })
        .toList(growable: false);
  }

  static Future<_ResponsibilityManifest> load(Directory root) async {
    final file = File(
      _join(root.path, '.architecture/protected_responsibilities.json'),
    );
    final json = _objectMap(jsonDecode(await file.readAsString()));
    final rawItems = json['responsibilities']! as List<Object?>;
    return _ResponsibilityManifest(
      rawItems
          .map((rawItem) {
            final item = _objectMap(rawItem);
            return _ProtectedResponsibility(
              id: item['id']! as String,
              protectedFiles: _stringList(item['protectedFiles']),
              verificationCommands: _stringList(item['verificationCommands']),
            );
          })
          .toList(growable: false),
    );
  }
}

class _ProtectedResponsibility {
  const _ProtectedResponsibility({
    required this.id,
    required this.protectedFiles,
    required this.verificationCommands,
  });

  final String id;
  final List<String> protectedFiles;
  final List<String> verificationCommands;
}

class _RepositorySnapshot {
  const _RepositorySnapshot(this.hashes);

  final Map<String, String> hashes;

  static Future<_RepositorySnapshot> capture(Directory root) async {
    final output = await _git(root, <String>[
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
    final paths = _nonEmptyLines(output).toSet().toList()..sort();
    final hashes = <String, String>{};
    for (final path in paths) {
      final file = File(_join(root.path, path));
      if (!await file.exists()) {
        hashes[path] = '<missing>';
        continue;
      }
      hashes[path] = (await _git(root, <String>[
        'hash-object',
        '--no-filters',
        '--',
        path,
      ])).trim();
    }
    return _RepositorySnapshot(hashes);
  }

  Set<String> changedPaths(_RepositorySnapshot other) {
    final paths = <String>{...hashes.keys, ...other.hashes.keys};
    return paths.where((path) => hashes[path] != other.hashes[path]).toSet();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'hashes': hashes,
  };

  static _RepositorySnapshot fromJson(Map<String, Object?> json) {
    final rawHashes = _objectMap(json['hashes']);
    return _RepositorySnapshot(
      rawHashes.map((path, hash) => MapEntry(path, hash! as String)),
    );
  }
}

class _GuardReport {
  const _GuardReport({
    required this.planId,
    required this.description,
    required this.createdAt,
    required this.changedPaths,
    required this.unexpectedPaths,
    required this.missingProtectedFiles,
    required this.protectedResponsibilities,
    required this.commandResults,
    required this.commandsSkipped,
  });

  final String planId;
  final String description;
  final DateTime createdAt;
  final List<String> changedPaths;
  final List<String> unexpectedPaths;
  final List<String> missingProtectedFiles;
  final List<String> protectedResponsibilities;
  final List<_CommandResult> commandResults;
  final bool commandsSkipped;

  bool get passed =>
      unexpectedPaths.isEmpty &&
      missingProtectedFiles.isEmpty &&
      commandResults.every((result) => result.exitCode == 0);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'planId': planId,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'passed': passed,
    'commandsSkipped': commandsSkipped,
    'changedPaths': changedPaths,
    'unexpectedPaths': unexpectedPaths,
    'missingProtectedFiles': missingProtectedFiles,
    'protectedResponsibilities': protectedResponsibilities,
    'commands': commandResults.map((result) => result.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Architecture guard report')
      ..writeln()
      ..writeln('- Plan: `$planId`')
      ..writeln('- Result: **${passed ? 'PASS' : 'FAIL'}**')
      ..writeln('- Created: `${createdAt.toIso8601String()}`')
      ..writeln('- Commands skipped: `$commandsSkipped`')
      ..writeln()
      ..writeln('## Changed paths')
      ..writeln();
    _writeList(buffer, changedPaths, emptyText: 'None');
    buffer
      ..writeln()
      ..writeln('## Unexpected paths')
      ..writeln();
    _writeList(buffer, unexpectedPaths, emptyText: 'None');
    buffer
      ..writeln()
      ..writeln('## Missing protected files')
      ..writeln();
    _writeList(buffer, missingProtectedFiles, emptyText: 'None');
    buffer
      ..writeln()
      ..writeln('## Protected responsibilities')
      ..writeln();
    _writeList(buffer, protectedResponsibilities, emptyText: 'None');
    buffer
      ..writeln()
      ..writeln('## Verification commands')
      ..writeln();
    if (commandResults.isEmpty) {
      buffer.writeln(commandsSkipped ? 'Skipped.' : 'None.');
    } else {
      for (final result in commandResults) {
        buffer.writeln(
          '- `${result.command}`: '
          '**${result.exitCode == 0 ? 'PASS' : 'FAIL'}** '
          '(exit ${result.exitCode})',
        );
      }
    }
    return buffer.toString();
  }

  static void _writeList(
    StringBuffer buffer,
    List<String> items, {
    required String emptyText,
  }) {
    if (items.isEmpty) {
      buffer.writeln(emptyText);
      return;
    }
    for (final item in items) {
      buffer.writeln('- `$item`');
    }
  }
}

class _CommandResult {
  const _CommandResult({
    required this.command,
    required this.exitCode,
    required this.standardOutput,
    required this.standardError,
  });

  final String command;
  final int exitCode;
  final String standardOutput;
  final String standardError;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'exitCode': exitCode,
    'standardOutput': standardOutput,
    'standardError': standardError,
  };
}

class _ReportFiles {
  const _ReportFiles({required this.markdown, required this.json});

  final File markdown;
  final File json;
}
