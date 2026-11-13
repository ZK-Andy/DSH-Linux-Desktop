import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { documentAnchors, findViolations, githubSlug, markdownLinkCache } from './verify-md-links.ts'
import { scratchRepo, type ScratchRepo } from './scratch-repo.ts'

const scratch: ScratchRepo[] = []

/** Create one throwaway scan root and register it for cleanup. */
function scratchRoot(): ScratchRepo {
  const repo = scratchRepo('md-links')
  scratch.push(repo)
  return repo
}

afterEach(() => {
  for (const repo of scratch.splice(0)) repo.dispose()
})

describe('githubSlug', () => {
  it('lowercases, drops punctuation, and turns spaces into hyphens', () => {
    expect(githubSlug('Hard-Wrapped Prose!')).toBe('hard-wrapped-prose')
    expect(githubSlug('中文 标题')).toBe('中文-标题')
    expect(githubSlug('Under_score ok')).toBe('under_score-ok')
  })
})

describe('documentAnchors', () => {
  it('collects heading slugs and explicit anchors', () => {
    const anchors = documentAnchors('# A\n\n## B c\n\n<a id="custom"></a>\n')

    expect([...anchors].sort()).toEqual(['a', 'b-c', 'custom'])
  })

  it('suffixes repeated headings the way GitHub occupies names', () => {
    expect([...documentAnchors('# Repeat\n\n# Repeat-1\n\n# Repeat\n')].sort()).toEqual([
      'repeat',
      'repeat-1',
      'repeat-2',
    ])
  })

  it('ignores anchors inside code and comments', () => {
    const anchors = documentAnchors('# A\n\n```html\n<a id="fenced"></a>\n```\n\n<!-- <a id="commented"></a> -->\n')

    expect([...anchors]).toEqual(['a'])
  })
})

describe('findViolations', () => {
  it('accepts a relative link that resolves', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '[b](b.md)\n')
    root.write('docs/b.md', '# B\n')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([])
  })

  it('reports a relative target that does not exist', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '[gone](missing.md)\n')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([
      { file: 'docs/a.md', line: 1, url: 'missing.md', reason: 'target' },
    ])
  })

  it('reports a fragment that names no anchor in the target', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '[b](b.md#nope)\n')
    root.write('docs/b.md', '# B\n')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([
      { file: 'docs/a.md', line: 1, url: 'b.md#nope', reason: 'anchor' },
    ])
  })

  it('accepts a fragment that names an anchor', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '[b](b.md#b)\n')
    root.write('docs/b.md', '# B\n')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([])
  })

  it('skips external and root-absolute links', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '# A\n\n[x](https://x.test) [y](/nowhere) [z](#a)\n')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([])
  })

  it('judges a same-file fragment against the document\'s own anchors', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '# A\n\n[z](#a)\n\n[w](#nowhere)\n')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([
      { file: 'docs/a.md', line: 5, url: '#nowhere', reason: 'anchor' },
    ])
  })

  it('does not judge fragments on non-Markdown targets', () => {
    const root = scratchRoot()
    root.write('docs/a.md', '[x](../scripts/a.ts#L10)\n')
    root.write('scripts/a.ts', '')

    expect(findViolations(join(root.root, 'docs/a.md'), markdownLinkCache(), root.root)).toEqual([])
  })
})
