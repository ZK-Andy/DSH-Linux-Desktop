import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { readOwnershipMarker, stripLineTerminator } from './install-lefthook.ts'

const OWNED_MARKER = JSON.stringify({
  owner: 'dsh-linux-desktop lefthook hooks',
  version: 1,
  hooksPath: '/repo/.git/dsh-hooks',
}, null, 2) + '\n'

describe('stripLineTerminator', () => {
  it('removes one trailing newline, keeping inner ones', () => {
    expect(stripLineTerminator('/repo\n')).toBe('/repo')
    expect(stripLineTerminator('/repo\r\n')).toBe('/repo')
    expect(stripLineTerminator('/a\n/b')).toBe('/a\n/b')
  })
})

describe('readOwnershipMarker', () => {
  let directory: string

  beforeEach(() => {
    directory = mkdtempSync(join(tmpdir(), 'dsh-lefthook-'))
  })

  afterEach(() => {
    rmSync(directory, { recursive: true, force: true })
  })

  it('accepts a marker this repository owns', () => {
    const markerPath = join(directory, 'owned')
    writeFileSync(markerPath, OWNED_MARKER)
    expect(readOwnershipMarker(markerPath)).toBe('/repo/.git/dsh-hooks')
  })

  it('rejects foreign owners, wrong versions, and relative hooks paths', () => {
    const cases = [
      '{"owner":"someone-else","version":1,"hooksPath":"/x"}\n',
      '{"owner":"dsh-linux-desktop lefthook hooks","version":2,"hooksPath":"/x"}\n',
      '{"owner":"dsh-linux-desktop lefthook hooks","version":1,"hooksPath":"x"}\n',
    ]
    for (const [index, content] of cases.entries()) {
      const markerPath = join(directory, `case-${String(index)}`)
      writeFileSync(markerPath, content)
      expect(readOwnershipMarker(markerPath)).toBeUndefined()
    }
  })

  it('rejects malformed JSON and missing files', () => {
    const markerPath = join(directory, 'broken')
    writeFileSync(markerPath, '{not json')
    expect(readOwnershipMarker(markerPath)).toBeUndefined()
    expect(readOwnershipMarker(join(directory, 'absent'))).toBeUndefined()
  })
})
