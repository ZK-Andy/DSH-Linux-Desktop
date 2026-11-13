/**
 * Run this repository's quality gates with bounded in-process scheduling.
 *
 * `package.json` owns the public aggregate names; this runner owns their
 * dependency graph, the scheduler environment, and process diagnostics.
 * Modes are deliberately few: this repository has one product, one artifact,
 * and one CI lane, so extra aggregates would only be aliases of each other.
 */
import { spawn } from 'node:child_process'
import { availableParallelism } from 'node:os'
import { resolve } from 'node:path'
import { performance } from 'node:perf_hooks'

/** A named aggregate exposed by the gate runner. */
export type Mode = 'check-all' | 'ci-static' | 'doc-quick'

type GateResultStatus = 'passed' | 'failed' | 'skipped'
type GateState = 'pending' | 'running' | GateResultStatus

/** A command and its dependency metadata inside one aggregate. */
export interface Gate {
  id: string
  label: string
  displayCommand: string
  command: string
  args: string[]
  /** Gate ids that must settle, regardless of outcome, before this gate starts. */
  after?: string[]
  /** Keep a failure visible without failing the aggregate. */
  allowFailure?: boolean
}

/** The observed outcome of one gate process. */
export interface GateResult {
  gate: Gate
  status: GateResultStatus
  durationMs: number
  exitCode: number | null
  signalCode: NodeJS.Signals | null
  output: string
  error?: string
}

const root = resolve(import.meta.dirname, '..')

/** Worker cap for the whole repository: every gate spawns at least one process, and several spawn a shell. */
const PROGRAM_MODE_CAP = 8

if (import.meta.main) {
  process.exitCode = await main(process.argv.slice(2))
}

/**
 * Run one named aggregate.
 * @param args - the mode name, as passed on the command line.
 * @returns the process exit code.
 */
async function main(args: string[]): Promise<number> {
  const mode = parseMode(args[0])
  const gates = gatesForMode(mode)
  return runAggregate(mode, gates)
}

/**
 * Validate the requested aggregate name.
 * @param raw - the first command-line argument.
 * @returns the matching mode.
 */
export function parseMode(raw: string | undefined): Mode {
  switch (raw) {
    case 'check-all':
    case 'ci-static':
    case 'doc-quick':
      return raw
    case undefined:
      throw new Error('run-gates: expected a mode (check-all | ci-static | doc-quick).')
    default:
      throw new Error(
        `run-gates: expected a mode (check-all | ci-static | doc-quick), got ${JSON.stringify(raw)}.`,
      )
  }
}

/**
 * Build one gate that invokes a repository script through this Node.
 * @param id - gate id, unique inside the aggregate.
 * @param script - repository-relative script path.
 * @param options - label and dependency overrides.
 * @returns the gate.
 */
function nodeGate(id: string, script: string, options: Partial<Gate> = {}): Gate {
  return {
    id,
    label: options.label ?? script,
    displayCommand: `node ${script}`,
    command: process.execPath,
    args: [script],
    ...options,
  }
}

/**
 * Build one gate that invokes a `package.json` script through pnpm.
 * @param id - gate id, unique inside the aggregate.
 * @param script - the `package.json` script name.
 * @param options - label and dependency overrides.
 * @returns the gate.
 */
function pnpmScript(id: string, script: string, options: Partial<Gate> = {}): Gate {
  return {
    id,
    label: options.label ?? script,
    displayCommand: `pnpm run ${script}`,
    command: 'pnpm',
    args: ['run', script],
    ...options,
  }
}

/**
 * Build one gate that invokes a shell script through bash.
 * @param id - gate id, unique inside the aggregate.
 * @param script - repository-relative shell script path.
 * @param options - label and dependency overrides.
 * @returns the gate.
 */
function shellGate(id: string, script: string, options: Partial<Gate> = {}): Gate {
  return {
    id,
    label: options.label ?? script,
    displayCommand: `bash ${script}`,
    command: 'bash',
    args: [script],
    ...options,
  }
}

/**
 * The gates that read only Markdown and Agent Notes: they need no build.
 * @returns the documentation leaf gates.
 */
function docLeafGates(): Gate[] {
  return [
    nodeGate('markdown-wrap', 'scripts/verify-md-wrap.ts', { label: 'markdown wrap' }),
    nodeGate('markdown-links', 'scripts/verify-md-links.ts', { label: 'markdown links' }),
    nodeGate('doc-budgets', 'scripts/verify-doc-budgets.ts', { label: 'documentation budgets' }),
    nodeGate('agent-note-classification', 'scripts/verify-agent-note-classification.ts', {
      label: 'Agent Note classification',
    }),
    nodeGate('agent-note-format', 'scripts/verify-agent-note-format.ts', { label: 'Agent Note format' }),
    nodeGate('archived-agent-notes', 'scripts/verify-archived-agent-notes.ts', { label: 'archived Agent Notes' }),
    nodeGate('skill-invocation-metadata', 'scripts/verify-skill-invocation-metadata.ts', {
      label: 'skill invocation metadata',
    }),
  ]
}

/**
 * The gates that read the gate scripts themselves.
 * @returns the script leaf gates.
 */
function scriptLeafGates(): Gate[] {
  return [
    pnpmScript('typecheck', 'typecheck', { label: 'gate script types' }),
    pnpmScript('lint', 'lint', { label: 'gate script lint' }),
    pnpmScript('test', 'test', { label: 'gate script tests' }),
    pnpmScript('duplication', 'duplication', { label: 'duplicated source' }),
  ]
}

/**
 * The gates that read the patch series and the scripts around it.
 * @returns the patch leaf gates.
 */
function patchLeafGates(): Gate[] {
  return [
    shellGate('patch-surface', 'scripts/patch-surface.sh', { label: 'patch surface' }),
    shellGate('shell-syntax', 'scripts/verify-shell-syntax.sh', { label: 'shell syntax' }),
  ]
}

/**
 * Construct the complete gate list for a named aggregate.
 * @param selected - aggregate mode to construct.
 * @returns the aggregate's gate graph.
 */
export function gatesForMode(selected: Mode): Gate[] {
  switch (selected) {
    case 'check-all':
      return [...docLeafGates(), ...patchLeafGates(), ...scriptLeafGates()]
    case 'ci-static':
      return [...docLeafGates(), ...patchLeafGates(), ...scriptLeafGates()]
    case 'doc-quick':
      return docLeafGates()
  }
}

/**
 * Resolve the worker count for one aggregate.
 * @param total - number of gates in the aggregate.
 * @param env - environment whose `DSH_GATE_CONCURRENCY` overrides the default.
 * @param cpus - CPU count Node reports for this process.
 * @returns the worker count and the source it came from.
 */
export function defaultConcurrency(
  total: number,
  env: NodeJS.ProcessEnv = process.env,
  cpus = availableParallelism(),
): { workers: number; source: string } {
  const budget = Math.max(1, Math.min(PROGRAM_MODE_CAP, cpus - 1))
  const override = env.DSH_GATE_CONCURRENCY
  if (override === undefined || override === '') {
    return { workers: Math.min(budget, Math.max(1, total)), source: `${String(cpus)} CPUs, capped at ${String(PROGRAM_MODE_CAP)}` }
  }
  const parsed = Number.parseInt(override, 10)
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    throw new Error(`run-gates: DSH_GATE_CONCURRENCY must be a positive integer, got ${JSON.stringify(override)}.`)
  }
  return { workers: Math.min(parsed, Math.max(1, total)), source: '$DSH_GATE_CONCURRENCY' }
}

/**
 * Reject dependency edges that name an unknown gate or form a cycle.
 * @param gates - the aggregate to validate.
 * @returns void; throws on an invalid graph.
 */
export function validateGateGraph(gates: readonly Gate[]): void {
  const ids = new Set(gates.map(gate => gate.id))
  if (ids.size !== gates.length) {
    throw new Error('run-gates: duplicate gate id in aggregate')
  }
  for (const gate of gates) {
    for (const dependency of gate.after ?? []) {
      if (!ids.has(dependency)) {
        throw new Error(`run-gates: gate ${gate.id} waits for unknown gate ${dependency}`)
      }
    }
  }
  const visiting = new Set<string>()
  const done = new Set<string>()
  const byId = new Map(gates.map(gate => [gate.id, gate]))
  const visit = (id: string): void => {
    if (done.has(id)) return
    if (visiting.has(id)) throw new Error(`run-gates: dependency cycle through gate ${id}`)
    visiting.add(id)
    for (const dependency of byId.get(id)?.after ?? []) visit(dependency)
    visiting.delete(id)
    done.add(id)
  }
  for (const gate of gates) visit(gate.id)
}

/**
 * Run one aggregate with bounded concurrency and a stable summary.
 * @param name - aggregate name printed in the start line.
 * @param gates - complete aggregate to execute.
 * @param env - environment selecting the worker count and fail-fast behaviour.
 * @returns 1 when a blocking gate failed, otherwise 0.
 */
export async function runAggregate(
  name: string,
  gates: Gate[],
  env: NodeJS.ProcessEnv = process.env,
): Promise<number> {
  validateGateGraph(gates)
  const { workers, source } = defaultConcurrency(gates.length, env)
  const failFast = env.DSH_GATE_FAIL_FAST === '1'
  const startedAt = performance.now()
  console.log(
    `run-gates: ${name} running ${String(gates.length)} gate(s) with ${String(workers)} worker(s) from ${source}`
    + `${failFast ? ', fail-fast after first blocking failure' : ''}.`,
  )
  const results = await runGates(gates, workers, failFast)
  for (const result of results) printResult(result)
  printSummary(results, performance.now() - startedAt)
  return results.some(result => result.gate.allowFailure !== true && result.status !== 'passed') ? 1 : 0
}

/**
 * Schedule gates, honouring `after` edges and the worker cap.
 * @param gates - aggregate to run.
 * @param workers - maximum concurrent gates.
 * @param failFast - stop scheduling once a blocking gate fails.
 * @returns every settled result, in completion order.
 */
export async function runGates(gates: readonly Gate[], workers: number, failFast: boolean): Promise<GateResult[]> {
  const states = new Map<string, GateState>(gates.map(gate => [gate.id, 'pending']))
  const results: GateResult[] = []
  const running = new Set<Promise<void>>()
  let stop = false

  const ready = (gate: Gate): boolean =>
    (gate.after ?? []).every(id => states.get(id) === 'passed' || states.get(id) === 'skipped')

  for (;;) {
    for (const gate of gates) {
      if (running.size >= workers) break
      if (states.get(gate.id) !== 'pending') continue
      if (stop && gate.allowFailure !== true) {
        states.set(gate.id, 'skipped')
        results.push({ gate, status: 'skipped', durationMs: 0, exitCode: null, signalCode: null, output: '' })
        continue
      }
      if (!ready(gate)) continue
      states.set(gate.id, 'running')
      const task = runGate(gate).then((result) => {
        states.set(gate.id, result.status)
        results.push(result)
        if (result.status === 'failed' && gate.allowFailure !== true && failFast) stop = true
      })
      running.add(task)
      task.finally(() => running.delete(task))
    }
    if (running.size === 0) break
    await Promise.race(running)
  }

  for (const gate of gates) {
    if (states.get(gate.id) === 'pending') {
      states.set(gate.id, 'skipped')
      results.push({ gate, status: 'skipped', durationMs: 0, exitCode: null, signalCode: null, output: '' })
    }
  }
  return results
}

/**
 * Run one gate to completion, capturing its combined output.
 * @param gate - the gate to execute.
 * @returns its result.
 */
export async function runGate(gate: Gate): Promise<GateResult> {
  const startedAt = performance.now()
  return await new Promise<GateResult>((resolveResult) => {
    const child = spawn(gate.command, gate.args, { cwd: root, env: process.env, stdio: ['ignore', 'pipe', 'pipe'] })
    let output = ''
    child.stdout.on('data', (chunk: Buffer) => { output += chunk.toString('utf8') })
    child.stderr.on('data', (chunk: Buffer) => { output += chunk.toString('utf8') })
    child.on('error', (error) => {
      resolveResult({
        gate,
        status: 'failed',
        durationMs: performance.now() - startedAt,
        exitCode: null,
        signalCode: null,
        output,
        error: error.message,
      })
    })
    child.on('close', (code, signal) => {
      resolveResult({
        gate,
        status: code === 0 ? 'passed' : 'failed',
        durationMs: performance.now() - startedAt,
        exitCode: code,
        signalCode: signal,
        output,
      })
    })
  })
}

/**
 * Print one settled gate.
 * @param result - the settled result.
 * @returns void.
 */
function printResult(result: GateResult): void {
  const status = result.status === 'passed' ? 'ok  ' : result.status === 'failed' ? 'FAIL' : 'skip'
  console.log(`${status}  ${result.gate.label}  (${formatDuration(result.durationMs)})`)
  const text = result.output.trim()
  if (text !== '' && result.status !== 'passed') {
    for (const line of text.split(/\r?\n/)) console.log(`      ${line}`)
  }
}

/**
 * Print the aggregate summary.
 * @param results - every settled result.
 * @param durationMs - wall clock spent.
 * @returns void.
 */
function printSummary(results: GateResult[], durationMs: number): void {
  const count = (status: GateResultStatus): number => results.filter(result => result.status === status).length
  console.log(
    `run-gates: ${String(count('passed'))} passed, ${String(count('failed'))} failed, `
    + `${String(count('skipped'))} skipped in ${formatDuration(durationMs)}.`,
  )
  for (const result of results) {
    if (result.status === 'failed') console.log(`run-gates: failed gate: ${result.gate.label}`)
  }
}

/**
 * Render a duration the way the summary reads.
 * @param durationMs - elapsed milliseconds.
 * @returns a short human-readable duration.
 */
function formatDuration(durationMs: number): string {
  return durationMs < 1000 ? `${String(Math.round(durationMs))}ms` : `${(durationMs / 1000).toFixed(1)}s`
}
