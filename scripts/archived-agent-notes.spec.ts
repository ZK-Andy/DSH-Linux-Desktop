import { describe, expect, it } from 'vitest'
import {
  extendArchiveManifest,
  parseArchiveManifest,
  renderArchiveManifest,
  validateArchiveArtifacts,
  validateArchiveManifestExtension,
} from './archived-agent-notes.ts'

const HASH = `sha256:${'a'.repeat(64)}`

/** One sealed note body that satisfies the archive metadata rules. */
function sealedNote(date = '2026-10-30'): string {
  return `# Agent Note: x\n\nStatus: implemented\nArchived: ${date}\n\n## Problem\n`
}

describe('parseArchiveManifest', () => {
  it('accepts exactly the version-1 shape', () => {
    expect(parseArchiveManifest(`{"version":1,"files":{"a/b.md":"${HASH}"}}`)).toEqual({
      version: 1,
      files: { 'a/b.md': HASH },
    })
  })

  it('rejects extra fields, other versions, and malformed hashes', () => {
    expect(() => parseArchiveManifest('{"version":1,"files":{},"extra":1}')).toThrow('exactly the fields')
    expect(() => parseArchiveManifest('{"version":2,"files":{}}')).toThrow('unsupported manifest version')
    expect(() => parseArchiveManifest('{"version":1,"files":{"a":"sha256:short"}}')).toThrow('invalid content hash')
    expect(() => parseArchiveManifest('[]')).toThrow('expected a JSON object')
  })
})

describe('renderArchiveManifest', () => {
  it('sorts paths and ends with a newline', () => {
    expect(renderArchiveManifest({ 'b/x.md': HASH, 'a/x.md': HASH })).toBe(
      `{\n  "version": 1,\n  "files": {\n    "a/x.md": "${HASH}",\n    "b/x.md": "${HASH}"\n  }\n}\n`,
    )
  })

  it('round-trips through the parser', () => {
    const files = { 'a/x.md': HASH }
    expect(parseArchiveManifest(renderArchiveManifest(files))).toEqual({ version: 1, files })
  })
})

describe('validateArchiveManifestExtension', () => {
  it('reports a removed or rehashed sealed entry', () => {
    const baseline = { version: 1 as const, files: { 'a/x.md': HASH, 'b/x.md': HASH } }
    const current = { version: 1 as const, files: { 'b/x.md': `sha256:${'b'.repeat(64)}` } }

    expect(validateArchiveManifestExtension(baseline, current)).toEqual([
      'a/x.md: sealed manifest entry is missing',
      'b/x.md: sealed manifest hash changed',
    ])
  })

  it('allows appending an entry', () => {
    const baseline = { version: 1 as const, files: {} }
    expect(validateArchiveManifestExtension(baseline, { version: 1, files: { 'a/x.md': HASH } })).toEqual([])
  })
})

describe('validateArchiveArtifacts', () => {
  it('accepts a sealed note under a known kind', () => {
    const artifacts = new Map([['feature/2026-10-30-x.md', Buffer.from(sealedNote())]])
    expect(validateArchiveArtifacts(artifacts)).toEqual([])
  })

  it('rejects a path outside {kind}/yyyy-mm-dd-topic.md', () => {
    const flat = new Map([['x.md', Buffer.from(sealedNote())]])
    expect(validateArchiveArtifacts(flat)).toEqual(['x.md: expected {kind}/yyyy-mm-dd-topic.md'])

    const undated = new Map([['feature/x.md', Buffer.from(sealedNote())]])
    expect(validateArchiveArtifacts(undated)).toEqual(['feature/x.md: expected {kind}/yyyy-mm-dd-topic.md'])
  })

  it('rejects an unknown kind instead of trusting the folder name', () => {
    const artifacts = new Map([['refactor/2026-10-30-x.md', Buffer.from(sealedNote())]])
    expect(validateArchiveArtifacts(artifacts)).toEqual([
      'refactor/2026-10-30-x.md: unknown Agent Note kind "refactor"',
    ])
  })

  it('requires the status line and the archive date immediately below it', () => {
    const noStatus = new Map([['feature/2026-10-30-x.md', Buffer.from('# Agent Note: x\n\n## Problem\n')]])
    expect(validateArchiveArtifacts(noStatus)).toContain('feature/2026-10-30-x.md: requires `Status: implemented`')

    const spaced = new Map([
      ['feature/2026-10-30-x.md', Buffer.from('# Agent Note: x\n\nStatus: implemented\n\nArchived: 2026-10-30\n')],
    ])
    expect(validateArchiveArtifacts(spaced)).toContain(
      'feature/2026-10-30-x.md: requires `Archived: YYYY-MM-DD` with a valid date immediately after the status',
    )
  })

  it('rejects an archive date earlier than the filename date', () => {
    const artifacts = new Map([['feature/2026-10-30-x.md', Buffer.from(sealedNote('2026-10-29'))]])
    expect(validateArchiveArtifacts(artifacts)).toEqual([
      'feature/2026-10-30-x.md: archive date 2026-10-29 predates the note filename',
    ])
  })
})

describe('extendArchiveManifest', () => {
  it('appends new artifacts and keeps sealed ones untouched', () => {
    const body = Buffer.from(sealedNote())
    const existing = { version: 1 as const, files: {} }

    const result = extendArchiveManifest(existing, new Map([['feature/2026-10-30-x.md', body]]))

    expect(result.added).toEqual(['feature/2026-10-30-x.md'])
    expect(result.errors).toEqual([])
    expect(result.files['feature/2026-10-30-x.md']).toMatch(/^sha256:[0-9a-f]{64}$/)
  })

  it('reports a sealed artifact that disappeared from the tree', () => {
    const existing = { version: 1 as const, files: { 'feature/2026-10-30-x.md': HASH } }
    expect(extendArchiveManifest(existing, new Map()).errors).toEqual([
      'feature/2026-10-30-x.md: sealed artifact is missing',
    ])
  })

  it('reports a sealed artifact whose bytes changed', () => {
    const existing = { version: 1 as const, files: { 'feature/2026-10-30-x.md': HASH } }
    const changed = new Map([['feature/2026-10-30-x.md', Buffer.from('edited')]])
    expect(extendArchiveManifest(existing, changed).errors).toEqual([
      'feature/2026-10-30-x.md: sealed content hash changed',
    ])
  })
})
