import { describe, expect, it } from 'vitest'
import { defaultConcurrency, gatesForMode, parseMode, validateGateGraph, type Gate } from './run-gates.ts'

/** A minimal gate with no work, for graph tests. */
function gate(id: string, after?: string[]): Gate {
  return { id, label: id, displayCommand: id, command: 'true', args: [], ...(after === undefined ? {} : { after }) }
}

describe('parseMode', () => {
  it('accepts the three aggregates', () => {
    expect(parseMode('check-all')).toBe('check-all')
    expect(parseMode('ci-static')).toBe('ci-static')
    expect(parseMode('doc-quick')).toBe('doc-quick')
  })

  it('names the accepted modes when the argument is missing or unknown', () => {
    expect(() => parseMode(undefined)).toThrow('expected a mode (check-all | ci-static | doc-quick)')
    expect(() => parseMode('check')).toThrow('got "check"')
  })
})

describe('gatesForMode', () => {
  it('runs the documentation gates alone in doc-quick', () => {
    const ids = gatesForMode('doc-quick').map(entry => entry.id)

    expect(ids).toContain('markdown-wrap')
    expect(ids).toContain('doc-budgets')
    expect(ids).not.toContain('patch-surface')
    expect(ids).not.toContain('duplication')
  })

  it('adds patch, type, lint, and duplication gates to check-all', () => {
    const ids = gatesForMode('check-all').map(entry => entry.id)

    expect(ids).toEqual(expect.arrayContaining(['patch-surface', 'shell-syntax', 'typecheck', 'lint', 'duplication']))
  })

  it('keeps check-all and ci-static in step', () => {
    const modes = new Set(['check-all', 'ci-static'])

    const shapes = [...modes].map(mode => gatesForMode(mode as 'check-all' | 'ci-static').map(entry => entry.id))
    expect(new Set(shapes.map(shape => shape.join(','))).size).toBe(1)
  })

  it('has a valid dependency graph in every mode', () => {
    for (const mode of ['check-all', 'ci-static', 'doc-quick'] as const) {
      expect(() => validateGateGraph(gatesForMode(mode))).not.toThrow()
    }
  })

  it('gives every gate a unique id', () => {
    const ids = gatesForMode('check-all').map(entry => entry.id)

    expect(new Set(ids).size).toBe(ids.length)
  })
})

describe('validateGateGraph', () => {
  it('rejects a duplicate id', () => {
    expect(() => validateGateGraph([gate('a'), gate('a')])).toThrow('duplicate gate id')
  })

  it('rejects an unknown dependency', () => {
    expect(() => validateGateGraph([gate('a', ['missing'])])).toThrow('waits for unknown gate missing')
  })

  it('rejects a cycle', () => {
    expect(() => validateGateGraph([gate('a', ['b']), gate('b', ['a'])])).toThrow('dependency cycle')
  })

  it('accepts a diamond', () => {
    expect(() => validateGateGraph([gate('a'), gate('b', ['a']), gate('c', ['a']), gate('d', ['b', 'c'])])).not.toThrow()
  })
})

describe('defaultConcurrency', () => {
  it('caps the worker count and never exceeds the gate count', () => {
    expect(defaultConcurrency(100, {}, 32).workers).toBe(8)
    expect(defaultConcurrency(3, {}, 32).workers).toBe(3)
    expect(defaultConcurrency(100, {}, 1).workers).toBe(1)
  })

  it('honours DSH_GATE_CONCURRENCY', () => {
    const result = defaultConcurrency(100, { DSH_GATE_CONCURRENCY: '2' }, 32)

    expect(result.workers).toBe(2)
    expect(result.source).toBe('$DSH_GATE_CONCURRENCY')
  })

  it('rejects a value that is not a positive integer', () => {
    expect(() => defaultConcurrency(10, { DSH_GATE_CONCURRENCY: '0' }, 8)).toThrow('must be a positive integer')
    expect(() => defaultConcurrency(10, { DSH_GATE_CONCURRENCY: 'x' }, 8)).toThrow('must be a positive integer')
  })
})
