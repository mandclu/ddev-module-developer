#!/usr/bin/env bats

# Absolute-host-path argument tests: commands should accept an absolute path on
# the host (e.g. from an IDE external tool or an AI agent) and rewrite it to the
# equivalent in-container path before invoking the underlying tool. Relative
# paths, flags, and absolute paths that do not resolve under the project root are
# passed through unchanged.

load helpers

setup_file() {
  set -eu -o pipefail

  export PROJNAME="test-module-developer-host-path-args"
  export TESTDIR="${HOME}/tmp/bats-ddev/${PROJNAME}"
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
  ddev config --project-type=drupal --project-name="${PROJNAME}" --docroot=web
  ddev add-on get "${DIR}"
  ddev start -y

  copy_fixture clean_module
}

teardown_file() {
  cd "${TESTDIR}" || true
  ddev delete -Oy || true
}

setup() {
  cd "${TESTDIR}"
  rm -rf vendor
  rm -f phpunit.xml phpunit.xml.dist phpcs.xml phpcs.xml.dist .phpcs.xml
}

teardown() {
  cd "${TESTDIR}"
  rm -rf vendor
  rm -f phpunit.xml phpunit.xml.dist phpcs.xml phpcs.xml.dist .phpcs.xml
}

@test "absolute host path argument is rewritten to the container path" {
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}"

  run ddev phpunit "${TESTDIR}/web/modules/custom/clean_module"
  assert_success
  assert_output --partial "LOCAL_PHPUNIT"
  assert_output --partial "ARGS:/var/www/html/web/modules/custom/clean_module"
}

@test "relative path argument is passed through unchanged" {
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}"

  run ddev phpunit web/modules/custom/clean_module
  assert_success
  assert_output --partial "ARGS:web/modules/custom/clean_module"
}

@test "absolute path that does not resolve under the project is left untouched" {
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}"

  run ddev phpunit /nonexistent/host/only/path
  assert_success
  assert_output --partial "ARGS:/nonexistent/host/only/path"
}

@test "phpcs rewrites an absolute host path passed as its argument" {
  make_shim "${TESTDIR}/vendor/bin/phpcs" LOCAL_PHPCS
  cat > "${TESTDIR}/phpcs.xml" <<'XML'
<?xml version="1.0"?>
<ruleset name="test">
  <rule ref="Drupal"/>
</ruleset>
XML
  cd "${TESTDIR}"

  run ddev phpcs "${TESTDIR}/web/modules/custom/clean_module"
  assert_success
  assert_output --partial "LOCAL_PHPCS"
  assert_output --partial "/var/www/html/web/modules/custom/clean_module"
}

@test "flags are preserved and only the absolute path argument is rewritten" {
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}"

  run ddev phpunit --stop-on-failure "${TESTDIR}/web/modules/custom/clean_module"
  assert_success
  assert_output --partial "ARGS:--stop-on-failure /var/www/html/web/modules/custom/clean_module"
}

@test "multiple absolute path arguments are each rewritten" {
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}"

  run ddev phpunit "${TESTDIR}/web/modules/custom/clean_module" \
                   "${TESTDIR}/web/modules/custom/clean_module/src"
  assert_success
  assert_output --partial "ARGS:/var/www/html/web/modules/custom/clean_module /var/www/html/web/modules/custom/clean_module/src"
}

@test "an absolute path containing spaces is rewritten as a single argument" {
  copy_fixture clean_module "clean module"
  make_shim "${TESTDIR}/vendor/bin/phpunit" LOCAL_PHPUNIT
  cat > "${TESTDIR}/phpunit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML
  cd "${TESTDIR}"

  run ddev phpunit "${TESTDIR}/web/modules/custom/clean module"
  assert_success
  assert_output --partial "ARGS:/var/www/html/web/modules/custom/clean module"
}
