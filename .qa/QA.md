# Project Quality Profile

<!-- project-quality:managed:start -->
## Generated project profile

- Profile schema: `1`
- Project-quality plugin: `0.2.0`
- Root type: `git`
- Files inventoried: `101`
- Monorepo detected: `no`
- Documentation-only: `no`

### Component map

| Path | Files |
| --- | ---: |
| `Libs` | 45 |
| `versions` | 22 |
| `tests` | 4 |
| `Media` | 2 |
| `.claude` | 1 |
| `.gitattributes` | 1 |
| `.github` | 1 |
| `.gitignore` | 1 |
| `.pkgmeta` | 1 |
| `.vscode` | 1 |
| `CHANGELOG.md` | 1 |
| `Core.lua` | 1 |
| `CurseForge_Description.md` | 1 |
| `Database.lua` | 1 |
| `DeathRollEnhancer.toc` | 1 |
| `DeathRollEnhancer_Camelot.toc` | 1 |
| `DeathRollEnhancer_Forever.toc` | 1 |
| `Dialogs.lua` | 1 |
| `embeds.xml` | 1 |
| `Events.lua` | 1 |
| `LICENSE` | 1 |
| `Minimap.lua` | 1 |
| `PROJECT_CONTEXT.md` | 1 |
| `README.md` | 1 |
| `RELEASE_PROCESS.md` | 1 |
| `scripts` | 1 |
| `TESTING.md` | 1 |
| `UI.lua` | 1 |
| `update-version.ps1` | 1 |
| `update-version.sh` | 1 |

### Languages

- Lua: 50 files
- Python: 3 files
- Shell: 1 files

### Important entry points

- No conventional entry point detected; inspect component manifests.

### Verification commands

Commands marked `declared` come from project manifests; `source-supported` commands come from static source evidence; `configured` commands come from reviewed overrides. No status implies the command has passed. Confirm `standard` and `inferred` commands before relying on them.
Commands use POSIX shell syntax. For PowerShell or cmd.exe, use the command working directory shown below and run the tool with native path handling; do not paste POSIX commands unchanged.

| Purpose | Command | Working directory | Evidence | Status |
| --- | --- | --- | --- | --- |
| test | `python3 -m unittest discover -s tests -v` | `.` | `tests/test_addon.py` | configured |
| package | `python3 scripts/build_release.py --version 2.3.10 --output dist/DeathRollEnhancer-2.3.10.zip` | `.` | `scripts/build_release.py` | configured |

### Critical workflows

- **test**: `python3 -m unittest discover -s tests -v`
- **package**: `python3 scripts/build_release.py --version 2.3.10 --output dist/DeathRollEnhancer-2.3.10.zip`

### Security boundaries

- No explicit evidence detected; treat this as an unknown boundary, not proof of absence.

### Data boundaries

- No explicit evidence detected; treat this as an unknown boundary, not proof of absence.

### Deployment boundaries

- `.github/workflows/release.yml`

### Active quality agents

- `quality_correctness` — Behavior, invariants, edge cases, regression coverage, and test gaps
- `quality_security` — Authentication, authorization, trust boundaries, secrets, inputs, and dependencies
- `quality_reliability` — Performance, concurrency, cleanup, resources, recovery, and resilience
- `quality_infrastructure` — Infrastructure, CI, deployment safety, permissions, and rollback
- `quality_custom_wow_compatibility` — WoW client compatibility, localization, and addon distribution readiness

### Verification matrix

| Change type | Minimum verification | Escalation |
| --- | --- | --- |
| Documentation/configuration | Parse or validate the changed format; review the relevant diff | Run broader checks when configuration affects builds or deployment |
| Local behavior | Focused regression test plus the nearest declared lint/type check | Run the full test suite when shared behavior or interfaces change |
| Security or trust boundary | Targeted negative and authorization tests | Require human review before changing credentials, production permissions, or policy |
| Schema or migration | Static validation and migration-specific tests only | Never run a live migration without separate authorization |
| Deployment/CI | Validate syntax and local build paths | Never deploy or mutate production without separate authorization |
| Published contract | Contract tests and representative consumer/build checks | Treat incompatible public API changes as release decisions |

### Exclusions and safety limits

- Generated dependencies, build outputs, VCS internals, and vendor directories are excluded from inventory by default.
- QA may edit supported local project files but never commits, pushes, deploys, changes production data, or runs live migrations without separate authorization.
- Generated review agents are read-only. The primary Codex agent owns all edits and verification.
- Findings require repository evidence; speculative checklist items are not defects.
<!-- project-quality:managed:end -->

## Human-maintained notes

<!-- project-quality:human:start -->
- Active addon files load from DeathRollEnhancer.toc in this order: Core.lua, Database.lua, UI.lua, Dialogs.lua, Events.lua, Minimap.lua. The versions/ directory contains archived snapshots, not current runtime modules.
- Required Ace3 modules are pinned and embedded (Libs/SOURCES.txt), loaded by embeds.xml before Core.lua. Runtime is WoW Lua with Ace3; host Lua 5.1 can verify syntax and isolated logic, but cannot validate protected APIs, event ordering, frame rendering, or live client compatibility.
- Baseline ad635ef had no automated tests. The repository now has Lua 5.1 regression tests using Lupa (tests/requirements.txt), package-reference checks, and a deterministic local ZIP builder. See TESTING.md. Tests use mocked client boundaries and do not certify in-game behavior.
- Critical workflows: fresh install/library loading; authoritative system-roll parsing and alternating turns; challenge acceptance; tab switching during play; SavedVariables history edit/delete/merge/dedupe; trade-wager settlement.
- Untrusted inputs include player-authored emotes and whispers. Emotes must not establish authoritative dice outcomes. Canonical player identities must distinguish realms.
- History is persistent user data. Legacy rows receive unique IDs without deduplication. legacyTotals preserves aggregate-only history; legacyStreaks checkpoints incomplete chronology. Destructive edits use stable IDs. An outcome edit before a legacy checkpoint triggers retained-row replay; wager-only edits preserve the checkpoint.
- Release packaging uses .pkgmeta and CurseForge version tokens. Verify dependency load order and an extracted install directory named DeathRollEnhancer before claiming install readiness.
- Client target and in-game smoke testing remain required to substantiate compatibility. Do not infer supported clients solely from TOC interface numbers.
- All initial reviewer reports were reconciled before fixes. The user subsequently authorized the primary agent to fix them; reviewers remain read-only. The user subsequently authorized research-backed Forever fixes, pushing, and release publication.
<!-- project-quality:human:end -->
