#!/usr/bin/env bash
# 生成 dnf 仓库的 repodata 并签名（repodata 放 gh-pages 的渠道目录，rpm 留在版本 Release）。
#
#   ./scripts/publish-repo.sh dist/dsh-desktop-0.2.2-rc.2-x86_64.rpm v0.2.2-rc.2-1 --channel nightly
#
# 产物（渠道决定目录，缺省 nightly）：
#   build/repo/<channel>/repodata/{primary.xml.gz,repomd.xml,repomd.xml.asc}
#   build/repo/<channel>/dsh-desktop.repo   # 给用户的仓库文件（两渠道两个 section）
#   build/repo/<channel>/legacy-root/repodata/   # 仅 nightly：迁移期给旧 .repo（baseurl 指站点根）
#
# 约定：rpm 的资产名必须与 href 一致，所以 Release 里的文件名就是这里传进来的文件名；
# 上传 Release 前先把 `~` 换成 `.`（GitHub 会规整字符，名字对不上 dnf 就 404）。
# 渠道只影响 gh-pages 上的目录布局：同一个 rpm、同一份 repodata 内容，渠道由 .repo 的
# baseurl 目录区分，所以 stable 与 nightly 各推各的目录、互不覆盖。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RPM_FILE="${1:?usage: $0 <rpm-file> <tag> [--channel stable|nightly] [--out DIR] [--baseurl URL] [--key-id ID] [--no-sign]}"
TAG="${2:?缺少 tag，例如 v0.2.2-rc.2-1}"
shift 2
CHANNEL=nightly
OUT=""
BASEURL=""
KEY_ID="${GPG_KEY_ID:-428BE141C85F90EE}"
SIGN=1
PAGES_BASEURL="${PAGES_BASEURL:-https://zk-andy.github.io/DSH-Linux-Desktop}"
REPO_TEMPLATE="$ROOT/packaging/dsh-desktop.repo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:?--channel 需要 stable 或 nightly}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --baseurl) BASEURL="${2:?}"; shift 2 ;;
    --key-id) KEY_ID="${2:?}"; shift 2 ;;
    --no-sign) SIGN=0; shift ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

case "$CHANNEL" in
  stable | nightly) ;;
  *) echo "未知渠道：$CHANNEL（只支持 stable 或 nightly）" >&2; exit 2 ;;
esac
OUT="${OUT:-$ROOT/build/repo/$CHANNEL}"

[[ -f "$RPM_FILE" ]] || { echo "找不到 rpm：$RPM_FILE" >&2; exit 2; }
[[ -f "$REPO_TEMPLATE" ]] || { echo "找不到仓库文件模板：$REPO_TEMPLATE" >&2; exit 2; }
BASEURL="${BASEURL:-https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/download/${TAG}/}"

rm -rf "$OUT"
mkdir -p "$OUT"
node "$ROOT/scripts/lib/make-repomd.ts" --rpm "$(dirname "$RPM_FILE")" --baseurl "$BASEURL" --out "$OUT"

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

# 发布用 .repo 由随包文件派生，保证两者只有一个事实来源：只改两处环境相关的值——
# 1) baseurl 前缀换成 Pages 站点（随包文件里已是同一个域名，默认即等价）；
# 2) gpgkey 换成本 Release 的公钥 URL：用户下载 .repo 时还没装包，本机没有
#    /etc/pki/rpm-gpg/ 下的文件，file:// 会让 dnf 校验仓库元数据失败。
sed -e "s|^baseurl=https://zk-andy.github.io/DSH-Linux-Desktop/|baseurl=${PAGES_BASEURL}/|" \
    -e "s|^gpgkey=.*|gpgkey=https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/latest/download/RPM-GPG-KEY-dsh-desktop|" \
    -e "s|^# 公钥由本包装在.*|# 公钥取自本 Release（装包后由 rpm 提供本机文件）|" \
    "$REPO_TEMPLATE" > "$OUT/dsh-desktop.repo"

# 迁移期：旧版应用的 dsh-desktop.repo 的 baseurl 是站点根目录，且只有一个 repo。
# 根目录继续等价 nightly（stable 也进 nightly），等旧应用换完再删这段。
if [[ "$CHANNEL" == nightly ]]; then
  mkdir -p "$OUT/legacy-root"
  cp -a "$OUT/repodata" "$OUT/legacy-root/repodata"
  echo "迁移期根目录镜像（等价 nightly）：$OUT/legacy-root/repodata"
fi

echo "仓库文件：$OUT/dsh-desktop.repo"
echo "下一步：把 $OUT/repodata 推到 gh-pages 的 $CHANNEL/ 目录；$OUT/dsh-desktop.repo 随包发布。"
