#!/usr/bin/env bats

# Installation and health tests for ddev-module-developer.
#
# Each @test creates its own DDEV project because the two install scenarios
# (directory vs. release) are mutually exclusive setups.
#
# Run (skip the release test locally):
#   bats tests/test.bats --filter-tags '!release'

load helpers

setup() {
  set -eu -o pipefail

  export GITHUB_REPO="mandclu/ddev-module-developer"
  export PROJNAME="test-module-developer"
  export TESTDIR="${HOME}/tmp/bats-ddev/${PROJNAME}"
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
  ddev config --project-type=drupal --project-name="${PROJNAME}" --docroot=web
  ddev start -y
}

teardown() {
  cd "${TESTDIR}" || true
  ddev delete -Oy || true
  rm -rf "${TESTDIR}"
}

# ---------------------------------------------------------------------------
# Installation tests
# ---------------------------------------------------------------------------

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} for project ${PROJNAME}" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
  # parallel-lint is installed by the Dockerfile in this add-on; verify the
  # binary is on PATH after the container is built from the local directory.
  run ddev exec "command -v parallel-lint"
  assert_success
  assert_output --partial "parallel-lint"
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} for project ${PROJNAME}" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
