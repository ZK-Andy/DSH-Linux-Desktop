#!/usr/bin/env bash
# 让 ./upstream 变成可构建的样子：按文件名顺序打进 patches/*.patch，再把补丁格式装不下的
# 二进制资产放到上游树里的落点。
#
#   ./scripts/apply-patches.sh          # 打补丁 + 放置资产
#   ./scripts/apply-patches.sh --check  # 只试打补丁，不落盘（资产不动）
#   ./scripts/apply-patches.sh --revert # 反打补丁 + 撤掉资产
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/upstream"
PATCH_DIR="$ROOT/patches"

# 补丁装不下的二进制资产：相对仓库根的源 → 在上游树里的落点。
#
# 托盘 PNG（补丁 0013 用）是二进制：贴进 patch 既不可读，也会被邮件/格式化工具改动，所以它不走
# patches/。它像上游的 resources/tray-windows.ico 一样直接住在源码树里，这一份存在我们仓库的
# assets/ 下，由本脚本放置。
# 补丁装不下的二进制资产：相对仓库根的源 → 在上游树里的落点。
#
# 托盘 PNG（补丁 0013 用）与 hicolor 尺寸集（补丁 0023 用）都是二进制：贴进 patch 既不可读，
# 也会被邮件/格式化工具改动，所以它们不走 patches/，存在我们仓库的 assets/ 下，由本脚本放置。
# 启动遮罩的 logo（apps/web/index.html 的启动壳）也是二进制，落进 Web 的 public 目录。
ASSETS=(
  'assets/tray-linux.png:apps/desktop/resources/tray-linux.png'
  'assets/icons-linux:apps/desktop/resources/icons-linux'
  'assets/icons-linux/512x512.png:apps/web/public/startup-logo.png'
  # 更新链的系统侧文件：helper 与 polkit 策略由 rpm %post 装到 /usr，签名公钥随应用发布。
  'assets/dsh-update-helper:apps/desktop/resources/dsh-update-helper:755'
  'assets/org.deepseek.harness.desktop.update.policy:apps/desktop/resources/org.deepseek.harness.desktop.update.policy:644'
  'assets/rpm-post-install.sh:apps/desktop/resources/rpm-post-install.sh:755'
  'assets/rpm-post-remove.sh:apps/desktop/resources/rpm-post-remove.sh:755'
  'packaging/RPM-GPG-KEY-dsh-desktop:apps/desktop/resources/RPM-GPG-KEY-dsh-desktop:644'
)

# 放置或撤掉上表里的资产。
# @param $1 remove 时删除，其余值安装
place_assets() {
  local action="$1" entry src target mode
  for entry in "${ASSETS[@]}"; do
    src="$ROOT/${entry%%:*}"
    target="$UPSTREAM/${entry#*:}"
    # 可选的第三段是权限位（755/644）；没有时按普通数据文件装。
    mode="644"
    if [[ "$target" == *:* ]]; then
      mode="${target##*:}"
      target="${target%:*}"
    fi
    if [[ "$action" == "remove" ]]; then
      [[ -e "$target" ]] || continue
      echo "==> remove ${entry#*:}"
      [[ -d "$target" ]] && rm -rf "$target" || rm -f "$target"
      continue
    fi
    [[ -e "$src" ]] || { echo "找不到 $src" >&2; exit 1; }
    echo "==> install ${target}"
    if [[ -d "$src" ]]; then
      mkdir -p "$target"
      cp -a "$src/." "$target/"
    else
      install -Dm"$mode" "$src" "$target"
    fi
  done
}

MODE="apply"
case "${1:-}" in
  --check)  MODE="check" ;;
  --revert) MODE="revert" ;;
  "")       ;;
  *) echo "未知参数：$1" >&2; exit 2 ;;
esac

[[ -d "$UPSTREAM/.git" ]] || { echo "找不到 $UPSTREAM，先跑 scripts/fetch-upstream.sh" >&2; exit 1; }

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if (( ${#patches[@]} == 0 )); then
  echo "==> patches/ 里没有 .patch 文件，无事可做"
  exit 0
fi

# --revert 要逆序撤销
if [[ "$MODE" == "revert" ]]; then
  for (( i=${#patches[@]}-1; i>=0; i-- )); do
    p="${patches[$i]}"
    echo "==> revert $(basename "$p")"
    git -C "$UPSTREAM" apply --reverse "$p"
  done
  place_assets remove
  echo "==> 全部撤销完成"
  exit 0
fi

for p in "${patches[@]}"; do
  name="$(basename "$p")"
  if [[ "$MODE" == "check" ]]; then
    echo "==> check $name"
    git -C "$UPSTREAM" apply --check "$p"
  else
    echo "==> apply $name"
    git -C "$UPSTREAM" apply "$p"
  fi
done

# 试打不落盘，资产也不动。
[[ "$MODE" == "check" ]] || place_assets install

echo "==> 完成（$MODE）"
