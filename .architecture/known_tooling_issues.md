# Known tooling issues

## Windows custom_lint startup

On 2026-08-15, targeted `dart analyze` reached the analysis server but the
project's existing `custom_lint` plugin failed to start with Windows error 193
and reported that `custom_lint_client.dart` was not an AOT snapshot. The same
command had previously reported no source errors and one resolved `close_sinks`
info before the plugin failure became fatal.

The V2 foundation is therefore validated by compilation through focused Flutter
tests and by the architecture guard's regression commands. Static analysis is a
separate open tooling verification and must not be reported as passing until the
plugin runtime issue is resolved.
