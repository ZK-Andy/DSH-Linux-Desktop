# Agent Note: rpm 签名，首装一次性导入公钥，helper 自动 import

Status: implemented

## Problem

dnf 校验签名需要 rpmdb 里有对应公钥。第三方签名的 rpm 在首次安装时必然缺少这把公钥，dnf 会以 NOKEY 拒绝。

## Decision

每个 rpm 都用仓库 GPG 私钥签名（私钥在 Actions secrets 里，`rpmsign --addsign`），公钥随包安装到 `/etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop` 并在 Release 里单列一份。首装是两步：先 `rpm --import` 公钥，再 `dnf5 install`。更新链由 helper 自动 `rpm --import`，用户只需授权一次。

## Alternatives considered

**不签名。** 安装要带 `--nogpgcheck`，等于把完整性校验整个关掉，也让仓库的 `gpgcheck` 失去意义。

**首装也用 helper 自动导入公钥。** helper 是装机之后才存在的文件，首装时还没有它；为了这一步在 README 里加一个 `pkexec` 调用，比 `rpm --import` 更绕。

## Consequences

README 的安装段落是两步，这是第三方签名 rpm 的标准做法。公钥导入失败时 helper 退 70，应用侧把它当作安装失败展示而不是静默继续。
