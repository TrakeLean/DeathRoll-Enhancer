<!-- project-quality:agents:start -->
## Project-quality agent routing

Read `.qa/QA.md` before quality-sensitive or cross-cutting project work. Use repository-local agents as read-only reviewers; the primary agent owns edits, tests, and the final decision.

For broad audits, run the three core agents in the first available parallel wave. Run applicable specialists afterward so they can use the core evidence without duplicating it. For ordinary work, involve only agents whose scope is materially affected:

- `quality_correctness`: Behavior, invariants, edge cases, regression coverage, and test gaps.
- `quality_security`: Authentication, authorization, trust boundaries, secrets, inputs, and dependencies.
- `quality_reliability`: Performance, concurrency, cleanup, resources, recovery, and resilience.
- `quality_infrastructure`: Infrastructure, CI, deployment safety, permissions, and rollback.
- `quality_custom_wow_compatibility`: WoW client compatibility, localization, and addon distribution readiness.

Require every delegated finding to include severity, evidence, file references, reproduction conditions, and a minimal correction. If parallel subagents are unavailable, evaluate the same scopes sequentially. Do not let review agents commit, push, deploy, access production data, or run live migrations.
<!-- project-quality:agents:end -->
