#!/usr/bin/env bash
# Shared preparation logic works from any current directory.
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$script_dir/scripts/prepare_version.py" "$@"
