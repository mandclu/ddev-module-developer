#!/usr/bin/env bats

# CI variable and generated-file cleanup tests.

load helpers

setup_file() {
  set -eu -o pipefail

  export PROJNAME="test-module-developer-ci-vars"
  export TESTDIR="${HOME}/tmp/bats-ddev/${PROJNAME}"
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
  ddev config --project-type=drupal --project-name="${PROJNAME}" --docroot=web
  ddev add-on get "${DIR}"
  ddev start -y

  copy_fixture clean_module
  copy_fixture dirty_module
}

teardown_file() {
  cd "${TESTDIR}" || true
  ddev delete -Oy || true
}

setup() {
  cd "${TESTDIR}"
  rm -f web/modules/custom/clean_module/.cspell.json \
        web/modules/custom/clean_module/.cspell.json.bak \
        web/modules/custom/clean_module/.cspell.expected.json \
        web/modules/custom/clean_module/.prettierrc.json \
        web/modules/custom/clean_module/.prettierignore \
        web/modules/custom/clean_module/.gitlab-ci.yml \
        web/modules/custom/dirty_module/.cspell.json \
        web/modules/custom/dirty_module/.cspell.json.bak \
        web/modules/custom/dirty_module/.gitlab-ci.yml
}

teardown() {
  cd "${TESTDIR}"
  rm -f web/modules/custom/clean_module/.cspell.json \
        web/modules/custom/clean_module/.cspell.json.bak \
        web/modules/custom/clean_module/.cspell.expected.json \
        web/modules/custom/clean_module/.prettierrc.json \
        web/modules/custom/clean_module/.prettierignore \
        web/modules/custom/clean_module/.gitlab-ci.yml \
        web/modules/custom/dirty_module/.cspell.json \
        web/modules/custom/dirty_module/.cspell.json.bak \
        web/modules/custom/dirty_module/.gitlab-ci.yml
}

@test "cspell: _CSPELL_WORDS from .gitlab-ci.yml is honoured" {
  cd "${TESTDIR}/web/modules/custom/dirty_module"
  cat > .gitlab-ci.yml <<'YAML'
variables:
  _CSPELL_WORDS: 'speling'
YAML

  run ddev cspell README.md
  assert_success
  [ ! -f .cspell.json ]
  [ ! -f .cspell.json.bak ]
}

@test "cspell: existing .cspell.json is restored after execution" {
  cd "${TESTDIR}/web/modules/custom/clean_module"
  cat > .cspell.json <<'JSON'
{"version":"0.2","words":["clean_module"]}
JSON
  cp .cspell.json .cspell.expected.json

  run ddev cspell clean_module.module
  assert_success
  run cmp .cspell.json .cspell.expected.json
  assert_success
  [ ! -f .cspell.json.bak ]
}

@test "eslint: generated prettier files are removed after fallback run" {
  cd "${TESTDIR}/web/modules/custom/clean_module"

  run ddev eslint js/good.js
  assert_success
  [ ! -e .prettierrc.json ]
  [ ! -e .prettierignore ]
}
