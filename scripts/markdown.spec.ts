import { describe, expect, it } from 'vitest'
import { parseMarkdown, markdownFences, markdownHeadingLines, markdownProseLines, isExternalOrAbsoluteMarkdownUrl, splitMarkdownUrlTarget } from './markdown.ts'

describe('isExternalOrAbsoluteMarkdownUrl', () => {
  it('accepts schemes, protocol-relative, root-absolute, and in-page links', () => {
    for (const url of ['https://x.test', 'mailto:a@b.test', '//x.test/a', '/docs/a.md', '#anchor']) {
      expect(isExternalOrAbsoluteMarkdownUrl(url)).toBe(true)
    }
  })

  it('rejects repository-relative targets', () => {
    for (const url of ['a.md', '../docs/a.md', './a.md']) {
      expect(isExternalOrAbsoluteMarkdownUrl(url)).toBe(false)
    }
  })
})

describe('splitMarkdownUrlTarget', () => {
  it('keeps the query and fragment suffix out of the path', () => {
    expect(splitMarkdownUrlTarget('a.md#L10')).toEqual({ path: 'a.md', suffix: '#L10' })
    expect(splitMarkdownUrlTarget('a.md?x=1#y')).toEqual({ path: 'a.md', suffix: '?x=1#y' })
    expect(splitMarkdownUrlTarget('a.md')).toEqual({ path: 'a.md', suffix: '' })
  })
})

describe('markdownProseLines', () => {
  it('reports one entry per source line outside fences', () => {
    const source = '# 标题\n\n第一段\n\n```sh\necho hi\n```\n'
    const lines = markdownProseLines(source).map(line => line.raw)

    expect(lines).toContain('第一段')
    expect(lines).not.toContain('echo hi')
  })
})

describe('markdownHeadingLines', () => {
  it('returns depth and rendered text', () => {
    const headings = markdownHeadingLines('## 二级 `code`\n\n### 三级\n')

    expect(headings.map(heading => [heading.depth, heading.text])).toEqual([
      [2, '二级 code'],
      [3, '三级'],
    ])
  })
})

describe('markdownFences', () => {
  it('reports language, info string, body, and closure', () => {
    const [fence] = markdownFences('```ts title=a\nconst x = 1\n```\n')

    expect(fence).toMatchObject({ line: 1, lang: 'ts', info: 'ts title=a', code: 'const x = 1', closed: true })
  })

  it('marks an unclosed fence', () => {
    expect(markdownFences('```sh\necho hi\n')[0]?.closed).toBe(false)
  })
})

describe('parseMarkdown', () => {
  it('parses GFM tables that plain Markdown would leave as text', () => {
    const tree = parseMarkdown('| a | b |\n|:--|:--|\n| 1 | 2 |\n')

    expect(tree.type).toBe('root')
    expect('children' in tree ? tree.children[0]?.type : undefined).toBe('table')
  })
})
