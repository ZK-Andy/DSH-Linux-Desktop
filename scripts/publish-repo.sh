#!/usr/bin/env bash
# 生成 dnf 仓库的 repodata 并签名（repodata 放 gh-pages，rpm 留在版本 Release）。
#
#   ./scripts/publish-repo.sh dist/dsh-desktop-0.2.2-alpha.2-x86_64.rpm v0.2.2-alpha.2-2
#
# 产物：
#   build/repo/repodata/{primary.xml.gz,repomd.xml,repomd.xml.asc}
#   build/repo/dsh-desktop.repo      # 给用户的仓库文件（baseurl 指向 Pages）
#
# 约定：rpm 的资产名必须与 href 一致，所以 Release 里的文件名就是这里传进来的文件名；
# 上传 Release 前先把 `~` 换成 `.`（GitHub 会规整字符，名字对不上 dnf 就 404）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RPM_FILE="${1:?usage: $0 <rpm-file> <tag> [--out DIR] [--baseurl URL] [--key-id ID] [--no-sign]}"
TAG="${2:?缺少 tag，例如 v0.2.2-alpha.2-2}"
shift 2
OUT="$ROOT/build/repo"
BASEURL=""
KEY_ID="${GPG_KEY_ID:-428BE141C85F90EE}"
SIGN=1
PAGES_BASEURL="${PAGES_BASEURL:-https://zk-andy.github.io/DSH-Linux-Desktop}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:?}"; shift 2 ;;
    --baseurl) BASEURL="${2:?}"; shift 2 ;;
    --key-id) KEY_ID="${2:?}"; shift 2 ;;
    --no-sign) SIGN=0; shift ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

[[ -f "$RPM_FILE" ]] || { echo "找不到 rpm：$RPM_FILE" >&2; exit 2; }
BASEURL="${BASEURL:-https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/download/${TAG}/}"

rm -rf "$OUT"
mkdir -p "$OUT"
python3 "$ROOT/scripts/lib/make-repomd.py" --rpm "$(dirname "$RPM_FILE")" --baseurl "$BASEURL" --out "$OUT"

if [[ "$SIGN" == 1 ]]; then
  GNUPGHOME="${GNUPGHOME:-$ROOT/.signing/gnupg}"
  export GNUPGHOME
  PASSPHRASE_FILE="${GPG_PASSPHRASE_FILE:-$ROOT/.signing/passphrase}"
  [[ -d "$GNUPGHOME" ]] || { echo "没有 GNUPGHOME：$GNUPGHOME（用 --no-sign 跳过签名）" >&2; exit 2; }
  gpg --batch --yes --pinentry-mode loopback \
    ${PASSPHRASE_FILE:+--passphrase-file "$PASSPHRASE_FILE"} \
    --local-user "$KEY_ID" --detach-sign --armor "$OUT/repodata/repomd.xml"
  gpg --verify "$OUT/repodata/repomd.xml.asc" "$OUT/repodata/repomd.xml" >/dev/null 2>&1 || {
    echo "repomd.xml 签名自验失败" >&2; exit 1; }
  echo "已签名：$OUT/repodata/repomd.xml.asc（$KEY_ID）"
else
  echo "跳过签名（--no-sign）"
fi

cat >"$OUT/dsh-desktop.repo" <<EOF
[dsh-desktop]
name=DSH Linux Desktop
baseurl=${PAGES_BASEURL}/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/latest/download/RPM-GPG-KEY-dsh-desktop
metadata_expire=6h
EOF

echo "仓库文件：$OUT/dsh-desktop.repo"
echo "下一步：把 $OUT/repodata 推到 gh-pages，把 dsh-desktop.repo 放进仓库打包或 README 指引。"
