param(
    [Parameter(Mandatory=$true)]
    [string]$NewVersion
)

# Shared preparation logic works from any current directory. Requires Python 3.
& python (Join-Path $PSScriptRoot 'scripts/prepare_version.py') $NewVersion
exit $LASTEXITCODE
