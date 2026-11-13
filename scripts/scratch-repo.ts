/** Throwaway repository roots for gate-script tests. */

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'

/** One temporary tree that cleans itself up when the test file finishes. */
export interface ScratchRepo {
  /** Absolute root of the temporary tree. */
  root: string
  /** Write one file relative to the root, creating its parent directories. */
  write: (path: string, content?: string) => void
  /** Remove the tree; safe to call more than once. */
  dispose: () => void
}

/**
 * Create a temporary repository root. Each call is independent, so a test may
 * hold several and dispose them in any order.
 * @param label - prefix for the temporary directory name, used for debuggability.
 * @returns the tree and its write/dispose helpers.
 */
export function scratchRepo(label: string): ScratchRepo {
  const root = mkdtempSync(join(tmpdir(), `${label}-`))
  return {
    root,
    write: (path, content = '') => {
      const abs = join(root, path)
      mkdirSync(dirname(abs), { recursive: true })
      writeFileSync(abs, content)
    },
    dispose: () => rmSync(root, { recursive: true, force: true }),
  }
}
