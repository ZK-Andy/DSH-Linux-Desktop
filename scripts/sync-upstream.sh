#!/usr/bin/env bash
# Fetch the pinned upstream tag into ./upstream (shallow, tag-only).
# Usage: scripts/sync-upstream.sh [tag]
set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:-${UPSTREAM_TAG:-dsh-v0.2.2-alpha.2}}"
url="${UPSTREAM_URL:-https://github.com/deepseek-ai/deepseek-harness.git}"

if [[ -d upstream/.git ]]; then
  echo "upstream: refreshing $tag"
  git -C upstream fetch --depth 1 origin "refs/tags/$tag:refs/tags/$tag"
  git -C upstream checkout --detach -f "tags/$tag"
  git -C upstream reset --hard "tags/$tag"
  git -C upstream clean -fdq
else
  echo "upstream: cloning $tag"
  git clone --depth 1 --branch "$tag" --single-branch "$url" upstream
fi

commit="$(git -C upstream rev-parse HEAD)"
echo "upstream: $tag @ $commit"
printf '%s %s\n' "$tag" "$commit" > upstream/.pinned
