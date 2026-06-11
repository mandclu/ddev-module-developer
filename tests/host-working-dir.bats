#!/usr/bin/env bats

# HostWorkingDir/default-target tests: commands run from inside a module should
# target that module/current directory when no explicit path is provided.

load helpers

setup_file() {
  set -eu -o pipefail

  export PROJNAME="test-module-developer-host-working-dir"
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
  rm -rf vendor
  rm -f phpunit.xml phpunit.xml.dist phpcs.xml phpcs.xml.dist .phpcs.xml
  rm -f web/modules/custom/clean_module/.prettierrc.json \
        web/modules/custom/clean_module/.prettierignore
}

teardown() {
  cd "${TESTDIR}"
  rm -rf vendor
  rm -f phpunit.xml phpunit.xml.dist phpcs.xml phpcs.xml.dist .phpcs.xml
  rm -f web/modules/custom/clean_module/.prettierrc.json \
        web/modules/custom/clean_module/.prettierignore
}

@test "phpcs: no path from clean module scans the current module" {
  cd "${TESTDIR}/web/modules/custom/clean_module"

  run ddev phpcs
  assert_success
}

@test "phpcs: no path from dirty module reports current-module violations" {
  cd "${TESTDIR}/web/modules/custom/dirty_module"

  run ddev phpcs
  assert_failure
  assert_output --partial "ERROR"
}

@test "stylelint: no pattern from clean module ignores dirty sibling module" {
  cd "${TESTDIR}/web/modules/custom/clean_module"

  run ddev stylelint
  assert_success
}

@test "eslint: no path from clean module ignores dirty sibling module" {
  cd "${TESTDIR}/web/modules/custom/clean_module"

  run ddev eslint
  assert_success
}

@test "phpunit: no path passes dot from the host working directory" {
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}/web/modules/custom/clean_module"

  run ddev phpunit
  assert_success
  assert_output --partial "LOCAL_PHPUNIT"
  assert_output --partial "PWD:/var/www/html/web/modules/custom/clean_module"
  assert_output --partial "ARGS:."
}
