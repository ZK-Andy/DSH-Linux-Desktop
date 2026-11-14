#!/usr/bin/env node
/**
 * Install the worktree-local Git hooks that run `lefthook.yml`.
 *
 * The hooks live in `<git-dir>/dsh-hooks` rather than `.git/hooks` so that
 * `git worktree add` gives every worktree its own copy: a shared `core.hooksPath`
 * would let one worktree's staged files drive another worktree's hooks.
 *
 * The script refuses to overwrite a `core.hooksPath` it does not own. Set
 * `DSH_LEFTHOOK_ALLOW_HOOKS_PATH_OVERRIDE=1` to take over an inherited path in
 * this worktree only.
 */
import { spawnSync } from 'node:child_process'
import type { SpawnSyncOptionsWithStringEncoding, SpawnSyncReturns } from 'node:child_process'
import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'

/** Oldest Git whose `--worktree` config scope we rely on. */
const MINIMUM_GIT = [2, 26, 0]

/** Directory name created inside the git directory to hold the hooks. */
const HOOKS_DIRECTORY = 'dsh-hooks'

/** Marker file that records which path this repository's hooks own. */
const OWNERSHIP_MARKER = '.dsh-lefthook-owned'
const OWNERSHIP_MARKER_VERSION = 1
const OWNERSHIP_MARKER_OWNER = 'dsh-linux-desktop lefthook hooks'

/** Environment variable that permits replacing an inherited `core.hooksPath`. */
const ALLOW_HOOKS_PATH_OVERRIDE = 'DSH_LEFTHOOK_ALLOW_HOOKS_PATH_OVERRIDE'

/** Result of one completed spawn with UTF-8 decoding. */
type CommandResult = SpawnSyncReturns<string>

/** Options for one spawn: working directory and tolerated non-zero statuses. */
type CaptureOptions = {
  cwd?: string | undefined
  allowStatuses?: number[] | undefined
}

/** Strip one trailing line terminator from command output. */
export function stripLineTerminator(text: string): string {
  return text.replace(/\r?\n$/, '')
}

/**
 * Run one command and fail loudly on a non-zero status.
 * @param command - executable to spawn.
 * @param args - its arguments.
 * @param options - working directory and tolerated statuses.
 */
function capture(command: string, args: string[], options: CaptureOptions = {}): CommandResult {
  const spawnOptions: SpawnSyncOptionsWithStringEncoding = options.cwd === undefined
    ? { encoding: 'utf8', env: process.env }
    : { cwd: options.cwd, encoding: 'utf8', env: process.env }
  const result = spawnSync(command, args, spawnOptions)
  if (result.status !== 0 && !(options.allowStatuses ?? []).includes(result.status ?? -1)) {
    const detail = typeof result.stderr === 'string' ? result.stderr.trim() : ''
    throw new Error(`${command} ${args.join(' ')} failed: ${detail || `exit status ${String(result.status)}`}`)
  }
  return result
}

/**
 * Run one Git command inside the repository.
 * @param args - Git arguments.
 * @param root - repository root.
 * @param options - statuses that are not failures.
 */
function git(args: string[], root: string, options: { allowStatuses?: number[] | undefined } = {}): CommandResult {
  return capture('git', args, { cwd: root, allowStatuses: options.allowStatuses })
}

/**
 * Read the installed `core.hooksPath` entries for one config file.
 * @param configPath - absolute config file path.
 * @param root - repository root, used as the cwd.
 * @returns every registered value, in file order.
 */
function hooksPathEntries(configPath: string, root: string): string[] {
  if (!existsSync(configPath)) return []
  const result = git(['config', '--file', configPath, '--get-all', 'core.hooksPath'], root)
  return result.status === 0 ? result.stdout.split(/\r?\n/).filter(Boolean) : []
}

/**
 * Validate the ownership marker's content.
 * @param markerPath - absolute marker path.
 * @returns the hooks path the marker names, when it is valid.
 */
export function readOwnershipMarker(markerPath: string): string | undefined {
  if (!existsSync(markerPath)) return undefined
  try {
    const parsed = JSON.parse(readFileSync(markerPath, 'utf8')) as { owner?: unknown; version?: unknown; hooksPath?: unknown }
    if (parsed.owner !== OWNERSHIP_MARKER_OWNER) return undefined
    if (parsed.version !== OWNERSHIP_MARKER_VERSION) return undefined
    if (typeof parsed.hooksPath !== 'string' || !parsed.hooksPath.startsWith('/')) return undefined
    return parsed.hooksPath
  } catch {
    return undefined
  }
}

/**
 * Create the hooks directory and its ownership marker.
 * @param hooksPath - absolute hooks directory path.
 */
function ensureOwnedHooksDirectory(hooksPath: string): void {
  if (existsSync(hooksPath)) {
    if (!lstatSync(hooksPath).isDirectory()) {
      throw new Error(`refusing to use non-directory hooks path ${hooksPath}`)
    }
    if (readOwnershipMarker(join(hooksPath, OWNERSHIP_MARKER)) === undefined) {
      throw new Error(`refusing to overwrite unowned hooks directory ${hooksPath}`)
    }
    return
  }
  mkdirSync(hooksPath, { mode: 0o700 })
  writeFileSync(
    join(hooksPath, OWNERSHIP_MARKER),
    `${JSON.stringify({ owner: OWNERSHIP_MARKER_OWNER, version: OWNERSHIP_MARKER_VERSION, hooksPath }, null, 2)}\n`,
    { flag: 'wx', mode: 0o600 },
  )
}

/**
 * Reject Git releases that predate the `--worktree` config scope.
 * @param root - repository root.
 */
function assertSupportedGit(root: string): void {
  const raw = stripLineTerminator(git(['--version'], root).stdout)
  const match = /(\d+)\.(\d+)\.(\d+)/.exec(raw)
  if (match === null) throw new Error(`cannot parse Git version from ${JSON.stringify(raw)}`)
  const actual = [Number(match[1]), Number(match[2]), Number(match[3])]
  for (let index = 0; index < MINIMUM_GIT.length; index += 1) {
    const current = actual[index] ?? Number.NaN
    const minimum = MINIMUM_GIT[index] ?? Number.NaN
    if (current > minimum) return
    if (current < minimum) {
      throw new Error(`Git ${MINIMUM_GIT.join('.')} or newer is required, found ${actual.join('.')}`)
    }
  }
}

/** Install the hooks into the current worktree. */
function install(): void {
  if (process.env.CI === 'true' || process.env.GITHUB_ACTIONS === 'true') return
  const probe = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' })
  if (probe.status !== 0) return
  const root = stripLineTerminator(probe.stdout)
  const lefthook = join(root, 'node_modules', '.bin', process.platform === 'win32' ? 'lefthook.cmd' : 'lefthook')
  if (!existsSync(lefthook)) return

  assertSupportedGit(root)
  const gitDirectory = stripLineTerminator(git(['rev-parse', '--absolute-git-dir'], root).stdout)
  const hooksPath = join(gitDirectory, HOOKS_DIRECTORY)
  const worktreeConfigPath = join(gitDirectory, 'config.worktree')
  const registered = hooksPathEntries(worktreeConfigPath, root)
  if (registered.length > 1) {
    throw new Error(`multiple core.hooksPath values in ${worktreeConfigPath}: ${registered.join(', ')}`)
  }
  if (registered.length === 1 && registered[0] !== hooksPath) {
    throw new Error(
      `refusing to replace worktree-scoped core.hooksPath ${String(registered[0])}; `
      + 'a worktree-specific custom path must be integrated or removed explicitly',
    )
  }

  const inherited = stripLineTerminator(
    git(['config', '--get', 'core.hooksPath'], root, { allowStatuses: [1] }).stdout,
  )
  if (inherited !== '' && inherited !== hooksPath && process.env[ALLOW_HOOKS_PATH_OVERRIDE] !== '1') {
    throw new Error(
      `refusing to replace user-owned core.hooksPath ${inherited}. `
      + `Chain those hooks through lefthook.yml, or rerun with ${ALLOW_HOOKS_PATH_OVERRIDE}=1`,
    )
  }

  ensureOwnedHooksDirectory(hooksPath)
  git(['config', '--worktree', 'core.hooksPath', hooksPath], root)
  const installed = spawnSync(lefthook, ['install', '--force'], { cwd: root, stdio: 'inherit', env: process.env })
  if (installed.status !== 0) {
    throw new Error(`lefthook install --force failed with exit status ${String(installed.status)}`)
  }
  console.log(`lefthook: hooks installed at ${hooksPath}`)
}

if (process.argv[1] && import.meta.filename === resolve(process.argv[1])) {
  try {
    install()
  } catch (error) {
    console.error(`install-lefthook: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  }
}
