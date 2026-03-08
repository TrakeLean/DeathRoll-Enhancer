param(
    [Parameter(Mandatory=$true)]
    [string]$NewVersion
)

Write-Host "Updating to version $NewVersion..." -ForegroundColor Green

# NOTE:
# Core.lua and DeathRollEnhancer.toc use CurseForge replacement tokens
# (@project-version@). Do not replace those with static versions.

# Update README.md
(Get-Content README.md) -replace '# DeathRoll Enhancer v[^ ]*', "# DeathRoll Enhancer v$NewVersion" | Set-Content README.md
(Get-Content README.md) -replace 'Version-[^-]*-brightgreen', "Version-$NewVersion-brightgreen" | Set-Content README.md
(Get-Content README.md) -replace '## What''s New in Version [0-9.]*', "## What's New in Version $NewVersion" | Set-Content README.md

# Update CHANGELOG.md (add new section at top)
$newChangelog = @"
# DeathRoll Enhancer - Changelog

## Version $NewVersion - SKEM Edition

### Bug Fixes
- [Add your changes here]

### New Features  
- [Add your changes here]

---

"@

$existingChangelog = Get-Content CHANGELOG.md | Select-Object -Skip 1
$newChangelog + ($existingChangelog -join "`n") | Set-Content CHANGELOG.md

Write-Host "Version updated to $NewVersion in all files!" -ForegroundColor Green
Write-Host "Don't forget to:" -ForegroundColor Yellow
Write-Host "1. Update CHANGELOG.md with actual changes" -ForegroundColor Yellow
Write-Host "2. Test the addon" -ForegroundColor Yellow  
Write-Host "3. Commit and push changes" -ForegroundColor Yellow
Write-Host "4. Create and push a git tag: git tag v$NewVersion; git push origin v$NewVersion" -ForegroundColor Yellow
