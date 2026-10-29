#!/usr/bin/env bash
# Apply (or check) the patches under ./patches against ./upstream.
# Usage: scripts/apply-patches.sh [--check]
# Replaying is idempotent per run: run against a pristine checkout, e.g.
#   scripts/sync-upstream.sh && scripts/apply-patches.sh
set -euo pipefail
cd "$(dirname "$0")/.."

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
fi

if [[ ! -d upstream/.git ]]; then
  echo "apply-patches: upstream/ is missing; run scripts/sync-upstream.sh first" >&2
  exit 1
fi

# Binary/large resources are not expressible as text patches: stage them here so
# the applied tree matches what a release build expects.
cp assets/tray-linux.png upstream/apps/desktop/resources/tray.png

shopt -s nullglob
patches=(patches/*.patch)
if [[ ${#patches[@]} -eq 0 ]]; then
  echo "apply-patches: no patches found" >&2
  exit 1
fi

for patch in "${patches[@]}"; do
  if (( check_only )); then
    echo "check $(basename "$patch")"
    git -C upstream apply --check "$PWD/$patch"
  else
    echo "apply $(basename "$patch")"
    git -C upstream apply "$PWD/$patch"
  fi
done
