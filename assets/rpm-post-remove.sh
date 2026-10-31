#!/bin/bash

# Delete the link to the binary
# update-alternatives --remove <name> <path>: 'path' must be the registered alternative binary,
# not the generic symlink — see https://man7.org/linux/man-pages/man1/update-alternatives.1.html
if type update-alternatives >/dev/null 2>&1; then
    update-alternatives --remove '${executable}' '/opt/${sanitizedProductName}/${executable}'
else
    rm -f '/usr/bin/${executable}'
fi

APPARMOR_PROFILE_DEST='/etc/apparmor.d/${executable}'

# Remove and unload apparmor profile.
if [ -f "$APPARMOR_PROFILE_DEST" ]; then
  # Unload the profile from the running kernel before deleting the file so the
  # policy is not left enforced until the next reboot.  Mirror the chroot guard
  # used in the after-install script — live AppArmor operations are not
  # meaningful inside a chroot.
  # https://wiki.debian.org/AppArmor/HowToUse
  if apparmor_status --enabled > /dev/null 2>&1; then
    if ! { [ -x '/usr/bin/ischroot' ] && /usr/bin/ischroot; } && hash apparmor_parser 2>/dev/null; then
      apparmor_parser --remove "$APPARMOR_PROFILE_DEST" || true
    fi
  fi
  rm -f "$APPARMOR_PROFILE_DEST"
fi

# --- DSH Linux Desktop: 卸载（不是升级）时撤掉随包导入的更新链公钥 ---
# key ID 必须与 packaging/RPM-GPG-KEY-dsh-desktop 一致，verify.sh 会核对两者。
if [ "$1" = "0" ]; then
  # rpm 把公钥存成 gpg-pubkey 包：NAME 固定、VERSION 是指纹，所以按指纹尾 8 位筛。
  # 用 rpmkeys --delete（rpm -e 删公钥从 4.x 起已废弃）。
  for fpr in $(rpm -qa --qf '%{NAME} %{VERSION}\n' 2>/dev/null \
      | awk '$1 == "gpg-pubkey" && substr($2, length($2) - 7) == "c85f90ee" { print $2 }'); do
    rpmkeys --delete "$fpr" > /dev/null 2>&1 || true
  done
fi
