#!/usr/bin/env bats
#
# canary.bats — sanity check for the bash test suite. If this fails,
# the test runner itself is broken; fix that before chasing other tests.

@test "canary: 1 == 1" {
  [ 1 -eq 1 ]
}

@test "canary: bash is available" {
  command -v bash
}
