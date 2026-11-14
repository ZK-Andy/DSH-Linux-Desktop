#!/usr/bin/env node
/**
 * 生成 dnf 仓库的 repodata（primary + repomd），只依赖 rpm 命令。
 *
 * 为什么不用 createrepo_c：发布机（GitHub Actions 之外）不一定装了它，
 * 而这套元数据只需要 rpm 头里的字段。格式按 repomd/primary 的规范写，
 * 字段集合与 createrepo_c 的输出对齐到 dnf5 能解析的最小完整集。
 *
 * 用法：
 *   node scripts/lib/make-repomd.ts --rpm <dir> --baseurl <url> --out <dir>
 * @module scripts/lib/make-repomd
 */

import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { basename, resolve } from 'node:path'
import { constants as zlibConstants, gzipSync } from 'node:zlib'
import { parseArgs } from 'node:util'

const QUERY = [
  '%{NAME}',
  '%{EPOCHNUM}',
  '%{VERSION}',
  '%{RELEASE}',
  '%{ARCH}',
  '%{SUMMARY}',
  '%{DESCRIPTION}',
  '%{PACKAGER}',
  '%{URL}',
  '%{BUILDTIME}',
  '%{LICENSE}',
  '%{VENDOR}',
  '%{GROUP}',
  '%{BUILDHOST}',
  '%{SOURCERPM}',
  '%{SIZE}',
].join('\t')

/** 运行 rpm 命令并返回 stdout；非零退出直接失败。 */
function runRpm(args: string[]): string {
  const [command = 'rpm', ...rest] = args
  const result = spawnSync(command, rest, { encoding: 'utf8' })
  if (result.status !== 0) {
    const detail = typeof result.stderr === 'string' ? result.stderr.trim() : ''
    const suffix = detail === '' ? '' : `: ${detail}`
    throw new Error(`Command '${args.join(' ')}' returned non-zero exit status ${String(result.status)}${suffix}`)
  }
  return result.stdout
}

/** 计算一个字节串或文件的 sha256。 */
function sha256(data: Buffer | string): string {
  return createHash('sha256').update(data).digest('hex')
}

/**
 * 把 '1.2.3 >= 4' 这种依赖拆成 (flags, ver)，与 rpm 的依赖语法一致。
 * 注意操作符两侧都要有空格才匹配——rpm 输出的行首操作符（'= 1.0'）不带前导空格，匹配不上。
 */
export function depFlags(version: string): [string, string] {
  const operators: Array<[string, string]> = [['>=', 'GE'], ['<=', 'LE'], ['==', 'EQ'], ['=', 'EQ'], ['>', 'GT'], ['<', 'LT']]
  for (const [operator, flag] of operators) {
    const marker = ` ${operator} `
    const at = version.indexOf(marker)
    if (at >= 0) return [flag, version.slice(at + marker.length).trim()]
  }
  return ['', '']
}

/** 与 Python xml.sax.saxutils.escape 对齐：只转义 & < >。 */
export function escapeXml(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
}

/** 与 Python xml.sax.saxutils.quoteattr 对齐：转义后按内容选引号，双引号优先。 */
export function quoteAttr(value: string): string {
  const escaped = escapeXml(value)
  if (!escaped.includes('"')) return `"${escaped}"`
  if (escaped.includes("'")) return `"${escaped.replaceAll('"', '&quot;')}"`
  return `'${escaped}'`
}

/** 由 rpm --provides / --requires 的输出行构造 <rpm:entry> 列表。 */
export function entries(lines: string[], isProvides: boolean): string {
  const out: string[] = []
  for (const raw of lines) {
    const line = raw.trim()
    if (line === '' || line.startsWith('rpmlib(')) continue
    // libfoo.so.1()(64bit) 这类带括号的 capability 原样保留（只在第一个空格处拆）
    const at = line.indexOf(' ')
    const name = at < 0 ? line : line.slice(0, at)
    const rest = at < 0 ? '' : line.slice(at + 1)
    const [flag, ver] = depFlags(rest)
    let attrs = `name=${quoteAttr(name)}`
    if (flag !== '') {
      attrs += ` flags="${flag}"`
      if (ver !== '') attrs += ` ver=${quoteAttr(ver)}`
    } else if (isProvides) {
      attrs += ' flags="EQ"'
    }
    out.push(`      <rpm:entry ${attrs}/>`)
  }
  return out.join('\n')
}

/** 读取一个 rpm 的头字段并渲染 <package> 块。 */
function packageXml(rpmPath: string, baseurl: string): string {
  const fields = runRpm(['rpm', '-qp', '--qf', QUERY, rpmPath]).split('\t')
  if (fields.length !== 16) {
    throw new Error(`rpm 查询字段数不对：${String(fields.length)}（${rpmPath}）`)
  }
  const [name, epoch, version, release, arch, summary, description, packager,
    url, buildtime, license, vendor, group, buildhost, sourcerpm, installedSize] = fields

  const provides = entries(runRpm(['rpm', '-qp', '--provides', rpmPath]).split('\n'), true)
  const requires = entries(runRpm(['rpm', '-qp', '--requires', rpmPath]).split('\n'), false)

  const stats = statSync(rpmPath)
  const size = stats.size
  const mtime = Math.trunc(stats.mtimeMs / 1000)
  const digest = sha256(readFileSync(rpmPath))

  return `  <package type="rpm">
    <name>${escapeXml(name ?? '')}</name>
    <arch>${escapeXml(arch ?? '')}</arch>
    <version epoch="${epoch === '' || epoch === undefined ? '0' : epoch}" ver="${escapeXml(version ?? '')}" rel="${escapeXml(release ?? '')}"/>
    <checksum type="sha256" pkgid="YES">${digest}</checksum>
    <summary>${escapeXml(summary ?? '')}</summary>
    <description>${escapeXml(description ?? '')}</description>
    <packager>${escapeXml(packager ?? '')}</packager>
    <url>${escapeXml(url ?? '')}</url>
    <time file="${String(mtime)}" build="${buildtime ?? ''}"/>
    <size package="${String(size)}" installed="${installedSize ?? ''}"/>
    <location xml:base=${quoteAttr(baseurl)} href=${quoteAttr(basename(rpmPath))}/>
    <format>
      <rpm:license>${escapeXml(license ?? '')}</rpm:license>
      <rpm:vendor>${escapeXml(vendor ?? '')}</rpm:vendor>
      <rpm:group>${escapeXml(group ?? '')}</rpm:group>
      <rpm:buildhost>${escapeXml(buildhost ?? '')}</rpm:buildhost>
      <rpm:sourcerpm>${escapeXml(sourcerpm ?? '')}</rpm:sourcerpm>
      <rpm:provides>
${provides}
      </rpm:provides>
      <rpm:requires>
${requires}
      </rpm:requires>
    </format>
  </package>
`
}

/** UTC 的 %Y%m%d%H%M%S。 */
function utcStamp(epochSeconds: number): string {
  const date = new Date(epochSeconds * 1000)
  const pad = (value: number): string => String(value).padStart(2, '0')
  return `${String(date.getUTCFullYear())}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}`
}

/** 生成 repodata；返回退出码。 */
function main(): number {
  const { values } = parseArgs({
    options: {
      rpm: { type: 'string' },
      baseurl: { type: 'string' },
      out: { type: 'string' },
    },
  })
  const rpmArg = values.rpm
  const baseurlArg = values.baseurl
  const outArg = values.out
  if (rpmArg === undefined || baseurlArg === undefined || outArg === undefined) {
    process.stderr.write('usage: node scripts/lib/make-repomd.ts --rpm <dir> --baseurl <url> --out <dir>\n')
    return 2
  }

  const rpmDir = resolve(rpmArg)
  const rpms = (existsSync(rpmDir) ? readdirSync(rpmDir) : [])
    .filter(fileName => fileName.endsWith('.rpm'))
    .sort()
    .map(fileName => resolve(rpmDir, fileName))
  if (rpms.length === 0) {
    process.stderr.write(`目录里没有 rpm：${rpmDir}\n`)
    return 2
  }

  const baseurl = baseurlArg.endsWith('/') ? baseurlArg : `${baseurlArg}/`
  const out = resolve(outArg)
  mkdirSync(resolve(out, 'repodata'), { recursive: true })

  const packages = rpms.map(rpmPath => packageXml(rpmPath, baseurl)).join('')
  const primary = Buffer.from(`<?xml version="1.0" encoding="UTF-8"?>
<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="${String(rpms.length)}">
${packages}</metadata>
`, 'utf8')

  const primaryPath = resolve(out, 'repodata', 'primary.xml.gz')
  const primaryGz = gzipSync(primary, { level: zlibConstants.Z_BEST_COMPRESSION })
  writeFileSync(primaryPath, primaryGz)

  const openDigest = sha256(primary)
  const closeDigest = sha256(primaryGz)
  const timestamp = Math.floor(Date.now() / 1000)
  const stamp = utcStamp(timestamp)
  const repomdPath = resolve(out, 'repodata', 'repomd.xml')

  const repomd = `<?xml version="1.0" encoding="UTF-8"?>
<repomd xmlns="http://linux.duke.edu/metadata/repo" xmlns:rpm="http://linux.duke.edu/metadata/rpm">
  <revision>${stamp}</revision>
  <data type="primary">
    <checksum type="sha256">${closeDigest}</checksum>
    <open-checksum type="sha256">${openDigest}</open-checksum>
    <location href="repodata/primary.xml.gz"/>
    <timestamp>${String(timestamp)}</timestamp>
    <size>${String(primaryGz.length)}</size>
    <open-size>${String(primary.length)}</open-size>
  </data>
</repomd>
`
  writeFileSync(repomdPath, repomd)
  console.log(`repodata: ${String(rpms.length)} 个包，baseurl=${baseurl}`)
  console.log(`  ${primaryPath}`)
  console.log(`  ${repomdPath}`)
  return 0
}

if (process.argv[1] && import.meta.filename === resolve(process.argv[1])) {
  try {
    process.exitCode = main()
  } catch (error) {
    console.error(`make-repomd: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  }
}
