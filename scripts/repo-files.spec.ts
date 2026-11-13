import { symlinkSync } from 'node:fs'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { findReferenceViolations, isArchivedAgentNotePath, uniqueRepoFiles } from './repo-files.ts'
import { scratchRepo, type ScratchRepo } from './scratch-repo.ts'

const scratch: ScratchRepo[] = []

/** Create one throwaway repository root and register it for cleanup. */
function scratchRoot(): ScratchRepo {
  const repo = scratchRepo('repo-files')
  scratch.push(repo)
  return repo
}

afterEach(() => {
  for (const repo of scratch.splice(0)) repo.dispose()
})

describe('isArchivedAgentNotePath', () => {
  it('accepts the frozen archive tree and rejects its siblings', () => {
    expect(isArchivedAgentNotePath('.agents/notes/archived/feature/x.md')).toBe(true)
    expect(isArchivedAgentNotePath('.agents/notes/implemented/feature/x.md')).toBe(false)
    expect(isArchivedAgentNotePath('docs/x.md')).toBe(false)
  })

  it('normalizes Windows separators before comparing', () => {
    expect(isArchivedAgentNotePath('.agents\\notes\\archived\\feature\\x.md')).toBe(true)
  })
})

describe('uniqueRepoFiles', () => {
  it('expands ** across zero or more directories', () => {
    const root = scratchRoot()
    root.write('docs/a.md')
    root.write('docs/deep/nested/b.md')
    root.write('docs/c.txt')

    const files = uniqueRepoFiles(root.root, ['docs/**/*.md'])

    expect(files.map(file => file.abs.slice(root.root.length + 1)).sort()).toEqual(['docs/a.md', 'docs/deep/nested/b.md'])
  })

  it('keeps a wildcard segment from matching dot entries, as node glob dot:false does', () => {
    const root = scratchRoot()
    root.write('docs/a.md')
    root.write('docs/.hidden/b.md')

    const files = uniqueRepoFiles(root.root, ['docs/*/*.md'])

    expect(files).toHaveLength(0)
  })

  it('folds a . segment away instead of matching nothing', () => {
    const root = scratchRoot()
    root.write('docs/a.md')

    expect(uniqueRepoFiles(root.root, ['./docs/./a.md'])).toHaveLength(1)
  })

  it('rejects glob syntax it cannot model instead of silently matching nothing', () => {
    const root = scratchRoot()
    root.write('docs/a.md')

    expect(() => uniqueRepoFiles(root.root, ['docs/{a,b}.md'])).toThrow(TypeError)
    expect(() => uniqueRepoFiles(root.root, ['docs/[ab].md'])).toThrow(TypeError)
    expect(() => uniqueRepoFiles(root.root, ['docs/**'])).toThrow(TypeError)
    expect(() => uniqueRepoFiles(root.root, ['docs/../docs/a.md'])).toThrow(TypeError)
    expect(() => uniqueRepoFiles(root.root, ['docs//a.md'])).toThrow(TypeError)
  })

  it('dedupes a symlinked file against its target by real path', () => {
    const root = scratchRoot()
    root.write('docs/real.md', '# real\n')
    symlinkSync(join(root.root, 'docs/real.md'), join(root.root, 'docs/alias.md'))

    const files = uniqueRepoFiles(root.root, ['docs/*.md'])

    expect(files).toHaveLength(1)
    expect(files[0]?.abs).toBe(join(root.root, 'docs/alias.md'))
  })

  it('never walks into a directory the caller skips', () => {
    const root = scratchRoot()
    root.write('docs/a.md')
    root.write('docs/archived/b.md')

    const files = uniqueRepoFiles(
      root.root,
      ['docs/**/*.md'],
      path => path.startsWith('docs/archived/'),
      dir => dir.startsWith('docs/archived'),
    )

    expect(files.map(file => file.abs.slice(root.root.length + 1))).toEqual(['docs/a.md'])
  })
})

describe('findReferenceViolations', () => {
  it('reports every rejected reference with its one-based line', () => {
    const root = scratchRoot()
    root.write('docs/a.md', 'see [a](missing.md)\nfine [b](ok.md)\nsee [c](gone.md)\n')

    const violations = findReferenceViolations(
      root.root,
      join(root.root, 'docs/a.md'),
      /\]\(([^)]+)\)/g,
      raw => raw.slice(2, -1),
      ref => ref !== 'ok.md',
    )

    expect(violations).toEqual([
      { file: 'docs/a.md', line: 1, ref: 'missing.md' },
      { file: 'docs/a.md', line: 3, ref: 'gone.md' },
    ])
  })

  it('leaves an excluded line range unscanned', () => {
    const root = scratchRoot()
    root.write('docs/a.md', 'see [a](missing.md)\n')

    const violations = findReferenceViolations(
      root.root,
      join(root.root, 'docs/a.md'),
      /\]\(([^)]+)\)/g,
      raw => raw.slice(2, -1),
      () => true,
      () => [0, 1],
    )

    expect(violations).toHaveLength(0)
  })
})
