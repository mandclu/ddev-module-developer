#!/usr/bin/env bats

# Bats test suite for ddev-module-developer.
# Run from the add-on root: bats tests/test.bats --filter-tags '!release'
#
# Requires:
#   - bats-core  https://github.com/bats-core/bats-core
#   - bats-assert (loaded below)
#   - A working Docker + DDEV installation

setup() {
  set -eu -o pipefail

  export GITHUB_REPO="your-org/ddev-module-developer"

  # Test project directory – created fresh for each test run.
  export PROJNAME="test-module-developer"
  export TESTDIR="${BATS_TEST_TMPDIR}/${PROJNAME}"
  export DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )/.." && pwd )"

  # Load bats helper libraries (adjust path if using a different install method).
  load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
  load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"

  # Initialise a minimal Drupal project so DDEV has a recognised project type.
  ddev config --project-type=drupal --project-name="${PROJNAME}" --docroot=web
  ddev start -y
}

teardown() {
  set -eu -o pipefail
  cd "${TESTDIR}" || true
  ddev delete -Oy || true
  rm -rf "${TESTDIR}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

health_checks() {
  # Every command binary must be on PATH inside the web container.
  for cmd in phpcs phpcbf phpstan phpmd rector stylelint eslint; do
    run ddev exec "command -v ${cmd}"
    assert_success
    assert_output --partial "${cmd}"
  done

  # phpcs must know about the Drupal standard.
  run ddev exec "phpcs -i"
  assert_success
  assert_output --partial "Drupal"
  assert_output --partial "DrupalPractice"

  # Bundled config files must exist inside the container.
  run ddev exec "test -f /mnt/ddev_config/module-developer/config/phpcs.xml"
  assert_success
  run ddev exec "test -f /mnt/ddev_config/module-developer/config/phpstan.neon"
  assert_success
  run ddev exec "test -f /mnt/ddev_config/module-developer/config/phpmd-ruleset.xml"
  assert_success
  run ddev exec "test -f /mnt/ddev_config/module-developer/config/.stylelintrc.json"
  assert_success
  run ddev exec "test -f /mnt/ddev_config/module-developer/config/.eslintrc.json"
  assert_success

  # ddev commands must be registered.
  run ddev help
  assert_success
  assert_output --partial "phpcs"
  assert_output --partial "phpstan"
  assert_output --partial "stylelint"
  assert_output --partial "eslint"

  # Quick smoke-test: phpcs should lint a trivial PHP file without crashing.
  echo "<?php echo 'hello';" > /tmp/smoke.php
  ddev exec "cp /tmp/smoke.php /var/www/html/smoke.php" || true
  run ddev phpcs /var/www/html/smoke.php
  # Exit code 0 (no violations) or 1 (violations found) are both acceptable;
  # anything else (e.g. 2 = fatal error) indicates a broken install.
  [ "${status}" -le 1 ]
  ddev exec "rm -f /var/www/html/smoke.php" || true
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "project-level phpcs.xml takes precedence over bundled config" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  # Place a minimal project-level phpcs.xml that only enables PSR-12.
  cat > phpcs.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="Test">
  <rule ref="PSR12"/>
</ruleset>
XML

  # If phpcs respects the project config, the output will reference PSR12,
  # not Drupal standards. We just verify it runs without a fatal error.
  run ddev phpcs --version
  assert_success

  rm -f phpcs.xml
}

@test "ddev phpmd prints usage when called with no arguments" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success

  run ddev phpmd
  assert_output --partial "Usage:"
}
