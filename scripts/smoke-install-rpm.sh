#!/usr/bin/env bash
# 安装冒烟：在 fedora:44 容器里 dnf5 装 rpm、启动、确认窗口、截图。
#
#   ./scripts/smoke-install-rpm.sh <含 *.rpm 的目录>
#
# 容器腿放在脚本里（与参考模板同形）：工作流只加一行 run，不把装包逻辑写进 YAML。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$(realpath "${1:?usage: $0 <dir-with-rpm>}")"
[[ -n "$(find "$PKG_DIR" -maxdepth 1 -name '*.rpm' -print -quit)" ]] || { echo "目录里没有 rpm：$PKG_DIR" >&2; exit 2; }

shots="$(mktemp -d)"
mkdir -p "$ROOT/shots"

docker run --rm \
  -v "$PKG_DIR:/pkg:ro" \
  -v "$shots:/shots:rw" \
  -v "$ROOT/scripts/smoke-rpm-inner.sh:/smoke-inner.sh:ro" \
  fedora:44 bash /smoke-inner.sh

cp "$shots"/*.png "$ROOT/shots/" 2>/dev/null || true
echo "截图：$(ls "$ROOT/shots" 2>/dev/null | tr '\n' ' ')"
