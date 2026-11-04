# DeathRoll Enhancer - Release Process

## GitHub releases

Run `bash update-version.sh <new-version>` or `./update-version.ps1 <new-version>` with Python 3 installed. The shared helper updates `VERSION`, the runtime fallback, README title/badge, and a new first changelog section. Fill in that section before publishing. Commit and push to `main`. The release workflow runs the Lua regression/package tests, builds the installable ZIP, then creates `v<VERSION>` and a GitHub release with the ZIP attached. It uses GitHub's repository token; no external upload credential is needed. Pull requests run verification without publishing. A manual workflow dispatch can retry an interrupted release; an existing release is never overwritten.

Download the attached `DeathRollEnhancer-<VERSION>.zip`, not GitHub's source archives. The source archives do not have the required installation folder or substituted version tokens.

## Optional: CurseForge Automatic Packaging

This repo is configured for CurseForge packager via:

- `.pkgmeta` in repo root
- `@project-version@` replacement tokens in:
  - `Core.lua`
  - `DeathRollEnhancer.toc`

### One-time setup

1. Generate a CurseForge API token (CurseForge Author Dashboard).
2. Add a GitHub webhook on this repository:
   - URL:
     `https://www.curseforge.com/api/projects/{projectID}/package?token={token}`
   - Content type: `application/json`
   - Trigger: `Just the push event`
3. Save webhook.

Notes:

- Keep the token in webhook settings only, never in git.
- Replace `{projectID}` with your CurseForge project ID.

### Release flow (beta/release/alpha)

1. Update docs/changelog as needed.
2. Commit and push to `main`.
3. Tag the release and push the tag:
   - Example:
     `git tag v2.3.3`
     `git push origin v2.3.3`
4. CurseForge will package automatically.

Tag behavior:

- Tags containing `alpha` => Alpha file (for example `v2.3.4-alpha.1`)
- Tags containing `beta` => Beta file (for example `v2.3.4-beta.1`)
- Other tags => Release file
- Untagged pushed commits package as Alpha if your CurseForge project is set to package all commits.

## Manual fallback (if webhook is unavailable)

1. Create a temporary `DeathRollEnhancer` folder.
2. Copy runtime files:
   - `Core.lua`, `Database.lua`, `UI.lua`, `Dialogs.lua`, `Events.lua`, `Minimap.lua`
   - `DeathRollEnhancer.toc`, `DeathRollEnhancer_Forever.toc`, `DeathRollEnhancer_Camelot.toc`
   - `Media/`
   - `embeds.xml` and `Libs/` (required embedded dependencies)
3. Zip that folder:
   ```powershell
   Compress-Archive -Path .\DeathRollEnhancer -DestinationPath .\versions\DeathRollEnhancer_vX.X.X.zip -Force
   ```
4. Verify the zip extracts into a top-level `DeathRollEnhancer` folder.

## Quick checklist

- [ ] Changelog updated
- [ ] Commit pushed
- [ ] Tag created and pushed
- [ ] CurseForge package created with expected release channel
- [ ] Installed and smoke-tested in game

## Verified local package

Run the tests in `TESTING.md`, then use the dependency-aware builder:

```sh
python3 scripts/build_release.py --version 2.4.0 --output dist/DeathRollEnhancer-2.4.0.zip
```

It validates every TOC/XML dependency, includes pinned libraries and licenses, replaces version tokens, and writes one installable `DeathRollEnhancer` directory. When copying manually, include `embeds.xml` and the complete `Libs/` directory before the runtime modules. Record the target-client smoke-test status in release notes. GitHub publication does not confirm CurseForge publication; that still depends on the separately configured webhook.
