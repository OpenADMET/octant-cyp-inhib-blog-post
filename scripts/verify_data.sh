#!/usr/bin/env bash
# Verify a local copy of the published parquet against the committed manifest.
set -euo pipefail
DIR="${1:-scratch/data}"
if [[ ! -d "$DIR" ]]; then
  echo "no dataset at '$DIR'. Stage it there first — see the Data section of README.md." >&2
  exit 1
fi
cd "$DIR"
sha256sum -c "$OLDPWD/data/MANIFEST.sha256"
