# DeathRoll Enhancer release process

A maintainer publishes a version by pushing one tag, `v<VERSION>`, on a verified commit from `main`. CurseForge builds its file from that tag through the repository webhook. GitHub Actions tests the same revision and attaches an installable ZIP to the GitHub release. Local ZIPs are for testing. Branch pushes, pull requests and manual workflow runs run verification only on GitHub.

## Before pushing a tag

1. Prepare the version with `./update-version.ps1 <new-version>` or `bash update-version.sh <new-version>`. Complete the new section in `CHANGELOG.md`, merge into `main`, and wait for the verification job to pass on the exact commit you intend to tag. Record the in-game smoke test results or outstanding checks in the release notes.
2. Check the remote tag with `git ls-remote --tags origin refs/tags/v<VERSION>`, substituting the value from `VERSION`. Check the project's **Files** and **Builds** in the author dashboard for the same version, including pending files, earlier uploads with custom display names and queued builds. If the version already has a file, keep its file ID and skip the tag push and upload. If a tag or build already exists, follow its progress using the recovery steps below. [CurseForge author files](https://authors.curseforge.com/#/projects/954561/files)
3. For a new release, confirm that the GitHub push webhook for CurseForge project `954561` is active and that CurseForge packaging is set to tagged commits only. The webhook credential belongs in GitHub webhook settings. The packager uses `.pkgmeta` and substitutes `@project-version@` in the addon. [CurseForge automatic packaging](https://support.curseforge.com/support/solutions/articles/9000197281)

## Publish once

1. Create `v<VERSION>` on the verified commit and push just that tag. For example, substitute the actual tag and commit in `git tag <tag> <verified-main-commit>` and `git push origin refs/tags/<tag>`. The tag push immediately triggers CurseForge packaging, independently of GitHub's release job. Use an `alpha` or `beta` suffix for the corresponding CurseForge channel.
2. Wait for the CurseForge build and file approval. Open the generated file in the author dashboard and record its file ID. For a title such as **v3.0.0 – Forever Celebration**, edit **Display name** on that file and save. A second ZIP upload creates a separate file.
3. Check the public **Files** list for exactly one entry for the version and channel. Open it and verify its title, file ID and supported game versions. Separately check that the GitHub release has the installable `DeathRollEnhancer-<VERSION>.zip` attached. [Public CurseForge files](https://www.curseforge.com/wow/addons/deathroll-enhancer/files/all)

## If publication is delayed or fails

Check the GitHub webhook delivery, CurseForge **Builds**, and the author **Files** list before retrying. An HTTP 200 acknowledges the webhook. A queued build or a file awaiting moderation can take time to appear publicly. If the public page or dashboard is inaccessible, pause publication until you can verify the version.

For a failed webhook delivery, confirm that no build or file exists for the tag, repair the webhook, then redeliver the original event once. For a failed GitHub release job, re-run the failed job on the original tag run. Keep the original tag in place. Both recovery paths use the original revision. Leave an existing CurseForge file in place and edit its metadata for title or description corrections.

## Local package for testing

Run the tests in [TESTING.md](TESTING.md), then build the installable ZIP:

```sh
python3 scripts/build_release.py --version "$(cat VERSION)" --output "dist/DeathRollEnhancer-$(cat VERSION).zip"
```

The builder validates TOC and XML dependencies, bundles the pinned libraries and licenses, and writes a single `DeathRollEnhancer` directory. For two-player Forever testing, install the same ZIP on both clients.
