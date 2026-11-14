import { describe, expect, it } from 'vitest'
import { depFlags, entries, escapeXml, quoteAttr } from './make-repomd.ts'

describe('escapeXml', () => {
  it('escapes only ampersand, less-than, and greater-than', () => {
    expect(escapeXml('a&b<c>d"e\'f')).toBe('a&amp;b&lt;c&gt;d"e\'f')
  })
})

describe('quoteAttr', () => {
  it('prefers double quotes and switches only on embedded quotes', () => {
    expect(quoteAttr('plain')).toBe('"plain"')
    expect(quoteAttr('a&b<c>d')).toBe('"a&amp;b&lt;c&gt;d"')
    expect(quoteAttr('has "double"')).toBe('\'has "double"\'')
    expect(quoteAttr('has \'single\' and "double"')).toBe('"has \'single\' and &quot;double&quot;"')
  })
})

describe('depFlags', () => {
  it('splits rpm dependency operators surrounded by spaces', () => {
    expect(depFlags(' >= 1.2')).toEqual(['GE', '1.2'])
    expect(depFlags(' <= 1.2')).toEqual(['LE', '1.2'])
    expect(depFlags(' == 1.2')).toEqual(['EQ', '1.2'])
    expect(depFlags(' = 1.2')).toEqual(['EQ', '1.2'])
    expect(depFlags(' > 1.2')).toEqual(['GT', '1.2'])
    expect(depFlags(' < 1.2')).toEqual(['LT', '1.2'])
    expect(depFlags('1.2.3')).toEqual(['', ''])
  })

  it('leaves leading operators bare (rpm output has no leading space on the line remainder)', () => {
    expect(depFlags('= 1.2-1')).toEqual(['', ''])
    expect(depFlags('>= 1.2')).toEqual(['', ''])
  })
})

describe('entries', () => {
  it('keeps bracketed capability names whole and marks provides without version as EQ', () => {
    expect(entries(['libfoo.so.1()(64bit)'], true))
      .toBe('      <rpm:entry name="libfoo.so.1()(64bit)" flags="EQ"/>')
  })

  it('renders versioned provides as EQ without ver (现状行为：depFlags 不匹配行首操作符)', () => {
    expect(entries(['dsh-desktop = 1.0-1'], true))
      .toBe('      <rpm:entry name="dsh-desktop" flags="EQ"/>')
  })

  it('renders unversioned requires bare', () => {
    expect(entries(['glib2'], false)).toBe('      <rpm:entry name="glib2"/>')
  })

  it('skips blank and rpmlib() lines', () => {
    expect(entries(['', 'rpmlib(FileCaps) <= 4.6.1-1', 'glib2'], false))
      .toBe('      <rpm:entry name="glib2"/>')
  })

  it('joins multiple entries with newlines', () => {
    expect(entries(['a', 'b'], false)).toBe('      <rpm:entry name="a"/>\n      <rpm:entry name="b"/>')
  })
})
