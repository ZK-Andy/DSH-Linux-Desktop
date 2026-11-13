#!/usr/bin/env bash
# 静态检查 scripts/ 下的 shell：语法、渠道判定函数的取值、以及每个脚本的可执行位。
# 用法：bash scripts/verify-shell-syntax.sh
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail=0

for script in scripts/*.sh scripts/lib/*.sh; do
  [ -e "$script" ] || continue
  if ! bash -n "$script"; then
    echo "!! 语法错误：$script"
    fail=1
  fi
done

# shellcheck disable=SC1091
source scripts/lib/release-channel.sh
case "$(release_channel_for_tag v0.2.2-rc.2-1)" in
  nightly) ;;
  *) echo '!! release_channel_for_tag v0.2.2-rc.2-1 应当是 nightly'; fail=1 ;;
esac
case "$(release_channel_for_tag v0.2.2-1)" in
  stable) ;;
  *) echo '!! release_channel_for_tag v0.2.2-1 应当是 stable'; fail=1 ;;
esac

# 入口脚本要被直接执行，缺可执行位在实际运行时才暴露，跑 CI 时已经晚了。
for entry in scripts/apply-patches.sh scripts/build.sh scripts/dev-desktop.sh scripts/fetch-upstream.sh \
  scripts/patch-surface.sh scripts/publish-repo.sh scripts/regen-patch.sh scripts/release-notes.sh \
  scripts/release-preflight.sh scripts/select-pnpm.sh scripts/smoke-install-rpm.sh scripts/smoke-rpm-inner.sh \
  scripts/verify.sh scripts/verify-shell-syntax.sh; do
  [ -e "$entry" ] || continue
  if [ ! -x "$entry" ]; then
    echo "!! 缺少可执行位：$entry"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

count=$(ls scripts/*.sh scripts/lib/*.sh 2>/dev/null | wc -l | tr -d ' ')
echo "verify-shell-syntax: ${count} 个脚本通过（语法、渠道判定、可执行位）"
