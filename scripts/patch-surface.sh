#!/usr/bin/env bash
# 静态检查 patches/：补丁首行说明、上游文件归属、main.ts 净增、资源副本、PLAN §10 引用一致性。
# 在重放补丁之前运行，未登记的违规以非 0 退出。
#
# PLAN.md §10「待迁移」是唯一登记处。每条检查只在「能唯一定位这一条违规」的字符串命中 §10 时
# 才算已登记：
#   - 首行：§10 里那句「没有补丁首行写」（M8 现状句；PR 2 补齐首行后必须删掉这句）；
#   - main.ts 净增：§10 的同一行里同时出现 `00NN`、main.ts、净增；
#   - 多补丁文件：§10 里出现该文件的完整路径；
#   - 内嵌资源：§10 里出现该落点的完整路径。
# §10 条目删掉后，对应检查自动变成硬失败。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

python3 - <<'PY'
import re
import pathlib
import sys

root = pathlib.Path('.')
plan = (root / 'PLAN.md').read_text(encoding='utf-8')
m = re.search(r'^## 10\. .*?(?=^## 11\.|\Z)', plan, re.M | re.S)
if not m:
    sys.exit('patch-surface: PLAN.md 找不到「## 10. 待迁移」')
migration = m.group(0)
lines = migration.splitlines()

patches = sorted((root / 'patches').glob('*.patch'))
if not patches:
    sys.exit('patch-surface: patches/ 为空')

failures: list[str] = []
registered: list[str] = []

def ok(message: str, *markers: str, line_only: bool = False) -> None:
    """任一 marker 在 §10 出现即视为已登记；line_only 时须同一行同时含全部 marker。"""
    hits = []
    if line_only:
        for line in lines:
            if all(marker and marker in line for marker in markers):
                hits.append(line.strip())
                break
    else:
        for marker in markers:
            if marker and marker in migration:
                hits.append(marker)
                break
    if hits:
        registered.append(message)
    else:
        failures.append(message)

def sections(patch: pathlib.Path):
    """yield (target, is_new, added, removed)，按 diff --git 分段统计。"""
    target = None
    is_new = False
    added = removed = 0
    for raw in patch.read_text(encoding='utf-8', errors='replace').splitlines():
        if raw.startswith('diff --git '):
            if target is not None:
                yield target, is_new, added, removed
            match = re.search(r' b/(.+)$', raw)
            target = match.group(1) if match else None
            is_new = False
            added = removed = 0
            continue
        if raw.startswith('new file mode'):
            is_new = True
            continue
        if raw.startswith('+++') or raw.startswith('---'):
            continue
        if raw.startswith('+'):
            added += 1
        elif raw.startswith('-'):
            removed += 1
    if target is not None:
        yield target, is_new, added, removed

def preamble(patch: pathlib.Path) -> str:
    out = []
    for raw in patch.read_text(encoding='utf-8', errors='replace').splitlines():
        if raw.startswith('diff --git '):
            break
        out.append(raw)
    return '\n'.join(out)

touched: dict[str, list[tuple[str, bool]]] = {}
for patch in patches:
    pre = preamble(patch)
    if not pre.splitlines() or not pre.splitlines()[0].startswith('变化理由：'):
        ok(f'{patch.name} 首行不是「变化理由：…」', '没有补丁首行写')
    for target, is_new, added, removed in sections(patch):
        touched.setdefault(target, []).append((patch.name, is_new))
        if target == 'apps/desktop/src/main.ts' and added - removed > 15 and '例外：规则 4' not in pre:
            ok(
                f'{patch.name} 的 main.ts 净增 {added - removed} 行，超过 15 且没有「例外：规则 4」行',
                f'`{patch.stem[:4]}`', 'main.ts', '净增', line_only=True,
            )

for target, entries in sorted(touched.items()):
    names = sorted({name for name, is_new in entries if not is_new})
    if target == 'apps/desktop/src/main.ts' or len(names) <= 1:
        continue
    ok(f'{target} 被 {len(names)} 个补丁触碰：{" ".join(names)}', target)

assets_src = (root / 'scripts/apply-patches.sh').read_text(encoding='utf-8')
block = re.search(r'^ASSETS=\((.*?)^\)', assets_src, re.M | re.S)
if not block:
    sys.exit('patch-surface: apply-patches.sh 找不到 ASSETS 表')
destinations: dict[str, str] = {}
for raw in block.group(1).splitlines():
    raw = raw.strip()
    if not raw or raw.startswith('#'):
        continue
    entry = raw.strip("'")
    src, _, rest = entry.partition(':')
    dest = rest.split(':')[0]
    if dest.startswith('apps/'):
        destinations[dest] = src
for dest, src in destinations.items():
    for patch in patches:
        for target, is_new, _, _ in sections(patch):
            if target == dest and is_new:
                ok(f'{patch.name} 内嵌了 {dest}，该文件由 apply-patches.sh 从 {src} 放置', dest)

for ref in sorted(set(re.findall(r'`(00\d{2})`', migration))):
    if not list((root / 'patches').glob(f'{ref}-*.patch')):
        failures.append(f'PLAN §10 引用的补丁 {ref} 不存在')

for message in registered:
    print(f'== 已登记（PLAN §10）：{message}')
if failures:
    for message in failures:
        print(f'!! 违规：{message}')
    sys.exit(1)
print(f'patch-surface: {len(patches)} 个补丁通过（未登记违规 0）')
PY
