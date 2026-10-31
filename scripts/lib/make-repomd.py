#!/usr/bin/env python3
"""生成 dnf 仓库的 repodata（primary + repomd），只依赖 rpm 命令。

为什么不用 createrepo_c：发布机（GitHub Actions 之外）不一定装了它，
而这套元数据只需要 rpm 头里的字段。格式按 repomd/primary 的规范写，
字段集合与 createrepo_c 的输出对齐到 dnf5 能解析的最小完整集。

用法：
  make-repomd.py --rpm <dir> --baseurl <url> --out <dir>
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

QUERY = "\t".join(
    [
        "%{NAME}",
        "%{EPOCHNUM}",
        "%{VERSION}",
        "%{RELEASE}",
        "%{ARCH}",
        "%{SUMMARY}",
        "%{DESCRIPTION}",
        "%{PACKAGER}",
        "%{URL}",
        "%{BUILDTIME}",
        "%{LICENSE}",
        "%{VENDOR}",
        "%{GROUP}",
        "%{BUILDHOST}",
        "%{SOURCERPM}",
        "%{SIZE}",
    ]
)


def rpm(args: list[str]) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dep_flags(version: str) -> tuple[str, str]:
    """把 '1.2.3 >= 4' 这种依赖拆成 (flags, ver)，与 rpm 的依赖语法一致。"""
    for token, flag in ((">=", "GE"), ("<=", "LE"), ("==", "EQ"), ("=", "EQ"), (">", "GT"), ("<", "LT")):
        marker = f" {token} "
        if marker in version:
            return flag, version.split(marker, 1)[1].strip()
    return "", ""


def entries(lines: list[str], is_provides: bool) -> str:
    out: list[str] = []
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("rpmlib("):
            continue
        if " " in line and "(" in line.split(" ", 1)[0] and ")" in line.split(" ", 1)[0]:
            # libfoo.so.1()(64bit) 这类带括号的 capability 原样保留
            pass
        name, _, rest = line.partition(" ")
        flag, ver = dep_flags(rest) if rest else ("", "")
        attrs = f'name={quoteattr(name)}'
        if flag:
            attrs += f' flags="{flag}"'
            if ver:
                attrs += f' ver={quoteattr(ver)}'
        elif is_provides:
            attrs += ' flags="EQ"'
        out.append(f"      <rpm:entry {attrs}/>")
    return "\n".join(out)


def package_xml(rpm_path: Path, baseurl: str) -> str:
    fields = rpm(["rpm", "-qp", "--qf", QUERY, str(rpm_path)]).split("\t")
    if len(fields) != 16:
        raise SystemExit(f"rpm 查询字段数不对：{len(fields)}（{rpm_path}）")
    (name, epoch, version, release, arch, summary, description, packager,
     url, buildtime, license_, vendor, group, buildhost, sourcerpm, installed) = fields

    provides = entries(rpm(["rpm", "-qp", "--provides", str(rpm_path)]).splitlines(), True)
    requires = entries(rpm(["rpm", "-qp", "--requires", str(rpm_path)]).splitlines(), False)

    size = rpm_path.stat().st_size
    digest = sha256(rpm_path)
    mtime = int(rpm_path.stat().st_mtime)

    return f"""  <package type="rpm">
    <name>{escape(name)}</name>
    <arch>{escape(arch)}</arch>
    <version epoch="{epoch or '0'}" ver="{escape(version)}" rel="{escape(release)}"/>
    <checksum type="sha256" pkgid="YES">{digest}</checksum>
    <summary>{escape(summary)}</summary>
    <description>{escape(description)}</description>
    <packager>{escape(packager)}</packager>
    <url>{escape(url)}</url>
    <time file="{mtime}" build="{buildtime}"/>
    <size package="{size}" installed="{installed}"/>
    <location xml:base={quoteattr(baseurl)} href={quoteattr(rpm_path.name)}/>
    <format>
      <rpm:license>{escape(license_)}</rpm:license>
      <rpm:vendor>{escape(vendor)}</rpm:vendor>
      <rpm:group>{escape(group)}</rpm:group>
      <rpm:buildhost>{escape(buildhost)}</rpm:buildhost>
      <rpm:sourcerpm>{escape(sourcerpm)}</rpm:sourcerpm>
      <rpm:provides>
{provides}
      </rpm:provides>
      <rpm:requires>
{requires}
      </rpm:requires>
    </format>
  </package>
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rpm", required=True, help="放 rpm 的目录（只会读其中的 *.rpm）")
    parser.add_argument("--baseurl", required=True, help="写进 <location xml:base> 的包下载前缀")
    parser.add_argument("--out", required=True, help="输出目录，会创建 repodata/")
    args = parser.parse_args()

    rpm_dir = Path(args.rpm).resolve()
    rpms = sorted(rpm_dir.glob("*.rpm"))
    if not rpms:
        print(f"目录里没有 rpm：{rpm_dir}", file=sys.stderr)
        return 2

    baseurl = args.baseurl if args.baseurl.endswith("/") else args.baseurl + "/"
    out = Path(args.out).resolve()
    (out / "repodata").mkdir(parents=True, exist_ok=True)

    packages = "".join(package_xml(path, baseurl) for path in rpms)
    primary = f"""<?xml version="1.0" encoding="UTF-8"?>
<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="{len(rpms)}">
{packages}</metadata>
""".encode()

    primary_path = out / "repodata" / "primary.xml.gz"
    with gzip.GzipFile(filename="", mode="wb", fileobj=primary_path.open("wb"), mtime=0) as stream:
        stream.write(primary)

    open_digest = hashlib.sha256(primary).hexdigest()
    close_digest = sha256(primary_path)
    timestamp = int(time.time())
    stamp = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y%m%d%H%M%S")

    repomd = f"""<?xml version="1.0" encoding="UTF-8"?>
<repomd xmlns="http://linux.duke.edu/metadata/repo" xmlns:rpm="http://linux.duke.edu/metadata/rpm">
  <revision>{stamp}</revision>
  <data type="primary">
    <checksum type="sha256">{close_digest}</checksum>
    <open-checksum type="sha256">{open_digest}</open-checksum>
    <location href="repodata/primary.xml.gz"/>
    <timestamp>{timestamp}</timestamp>
    <size>{primary_path.stat().st_size}</size>
    <open-size>{len(primary)}</open-size>
  </data>
</repomd>
"""
    (out / "repodata" / "repomd.xml").write_text(repomd)
    print(f"repodata: {len(rpms)} 个包，baseurl={baseurl}")
    print(f"  {out / 'repodata' / 'primary.xml.gz'}")
    print(f"  {out / 'repodata' / 'repomd.xml'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
