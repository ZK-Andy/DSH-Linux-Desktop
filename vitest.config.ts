import { defineConfig } from 'vitest/config'

/**
 * Gate script tests. They read and write nothing outside `scripts/`, so one
 * process pool with the repository's Node is enough.
 */
export default defineConfig({
  test: {
    include: ['scripts/**/*.spec.ts'],
    environment: 'node',
    reporters: ['default'],
  },
})
