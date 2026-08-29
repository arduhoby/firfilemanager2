# Fir File Manager project instructions

## Codex Multi-Model Routing

The primary agent is the final decision maker and uses `gpt-5.6-sol` for orchestration. Users should not need to choose a model for normal work; route work automatically when delegation is useful.

- Use `terra-worker` for standard implementation work: coordinated features, business logic, integrations, state management, debugging, and medium refactors.
- Use `luna-worker` for explicit, repetitive, low-risk, easily testable work such as boilerplate, DTOs, mappers, localization, fixtures, mocks, mechanical edits, and straightforward tests.
- Use `architect` for complex, ambiguous, architectural, cross-module, destructive, security-sensitive, concurrency-sensitive, migration, or high data-loss-risk decisions.
- Use `explorer` before broad changes when repository ownership, execution paths, dependencies, or reusable implementations are not yet clear. Keep exploration read-only.
- Use `tester` for bounded test creation and failure classification. Escalate complex or high-risk test work to Terra or Sol.
- Use `reviewer` only for broad or high-risk changes and critical correctness, security, concurrency, migration, destructive-operation, or data-loss review. Keep review read-only.

Prefer the lowest-cost model that can reliably complete the work, in this order: correctness, safety, user requirements, lowest sufficient model, then speed.

Estimate complexity, risk, ambiguity, and scope for each meaningful phase. Route simple work to Luna, normal coordinated work to Terra, and difficult or high-risk decisions to Sol. Treat this as judgment guidance, not a rigid scoring formula.

Escalate `luna-worker` to `terra-worker`, then to the primary Sol agent or `architect`, when complexity, ambiguity, scope, or risk increases. After Sol settles an architectural decision, de-escalate bounded implementation to Terra or Luna. The primary agent integrates results and performs critical final checks when justified.

Parallelize independent exploration, tests, analysis, or implementation tasks when it materially improves speed and the agents will not edit the same files. Avoid parallel write-heavy work that creates merge conflicts. Wait for delegated work, integrate it, run proportional validation, and report one consolidated result.

Small tasks should be completed directly when delegation overhead would exceed the benefit. A user request naming a specific model or agent takes precedence over automatic routing.
