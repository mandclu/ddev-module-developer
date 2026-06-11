#!/usr/bin/env bash
# Shared helpers for ddev-module-developer bats tests.
# Loaded by each test file via: load helpers

load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load"

# Copy a fixture directory from tests/testdata into the active DDEV project.
# Removes any stale destination first so deleted testdata files don't persist.
# Usage: copy_fixture <fixture-name> [<dest-module-name>]
copy_fixture() {
  local src="${1}" dest="${2:-${1}}"
  mkdir -p "${TESTDIR}/web/modules/custom"
  rm -rf "${TESTDIR}/web/modules/custom/${dest}"
  cp -r "${BATS_TEST_DIRNAME}/testdata/${src}" "${TESTDIR}/web/modules/custom/${dest}"
}

remove_fixture() {
  rm -rf "${TESTDIR}/web/modules/custom/${1}"
}

# Create an executable test binary that prints a sentinel, cwd, and arguments.
# Usage: make_shim <path> <label>
make_shim() {
  local path="${1}" label="${2}"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<SHIM
#!/usr/bin/env bash
echo "${label}"
echo "PWD:\$(pwd)"
echo "ARGS:\$*"
exit 0
SHIM
  chmod +x "${path}"
}

# Verify every tool binary is on PATH, all bundled configs are present,
# and all commands are registered with ddev.
health_checks() {
  # Every command binary must be on PATH inside the web container.
  # phpcompat is excluded: it is a DDEV command script that calls an isolated
  # /usr/local/phpcompat/vendor/bin/phpcs — no standalone binary is on PATH.
  # parallel-lint is installed at container build time. It is not asserted here
  # because older images (pre-rebuild) will not have it yet; fixtures.bats has
  # dedicated tests for both the installed and not-installed paths.
  for cmd in phpcs phpcbf phpstan phpmd rector stylelint eslint cspell phpunit; do
    run ddev exec "command -v ${cmd}"
    assert_success
    assert_output --partial "${cmd}"
  done

  # phpcompat: verify the isolated phpcs 3.x install that the command script uses.
  run ddev exec "test -x /usr/local/phpcompat/vendor/bin/phpcs"
  assert_success

  # phpcs must recognise the Drupal and DrupalPractice standards.
  run ddev exec "phpcs -i"
  assert_success
  assert_output --partial "Drupal"
  assert_output --partial "DrupalPractice"

  # All bundled config files must be present inside the container.
  for cfg in phpcs.xml phpstan.neon phpmd-ruleset.xml .stylelintrc.json .eslintrc.json; do
    run ddev exec "test -f /mnt/ddev_config/module-developer/config/${cfg}"
    assert_success
  done

  # All commands must appear in ddev help.
  run ddev help
  assert_success
  for cmd in checks parallel-lint phpcs phpcbf phpstan phpmd rector stylelint eslint cspell phpunit phpcompat; do
    assert_output --partial "${cmd}"
  done

  # phpcs smoke-test: exit 0 (clean) or 1 (violations) are fine; 2+ is a fatal error.
  ddev exec "printf '<?php\necho 1;\n' > /tmp/smoke.php"
  run ddev phpcs /tmp/smoke.php
  [ "${status}" -le 1 ]
  ddev exec "rm -f /tmp/smoke.php"
}
