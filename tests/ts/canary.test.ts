// canary.test.ts — sanity check for the TS test suite. If this
// fails, the test runner itself is broken; fix that before chasing
// other tests.

import { describe, expect, test } from "bun:test";

describe("canary", () => {
  test("1 === 1", () => {
    expect(1).toBe(1);
  });

  test("bun runtime is reachable", () => {
    expect(typeof Bun).toBe("object");
  });
});
