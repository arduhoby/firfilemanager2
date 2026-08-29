# Fir File Manager V2 architecture guard

This directory contains the development-time guardrails for the V2 migration.
The guard compares repository state before and after every migration step,
checks the declared file scope, runs responsibility-specific verification
commands, and writes Markdown and JSON reports.

The runtime application does not inspect its own source tree. Runtime file
operations use the operation verifier; source-code preservation is enforced by
`tool/architecture_guard.dart` during development and CI.

## Usage

```powershell
dart run tool/architecture_guard.dart verify --plan .architecture/plans/foundation.json
```

The command fails when an undeclared file changes, a protected file disappears,
UTF-8 validation fails, or a verification command returns a non-zero exit code.

