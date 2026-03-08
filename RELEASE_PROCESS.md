# DeathRoll Enhancer - Release Process

## Recommended: CurseForge Automatic Packaging

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
   - `Core.lua`, `Database.lua`, `UI.lua`, `Events.lua`, `Minimap.lua`
   - `DeathRollEnhancer.toc`
   - `Media/`
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
