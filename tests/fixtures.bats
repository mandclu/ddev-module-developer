#!/usr/bin/env bats

# Per-command detection tests using fixture modules with intentional violations.
#
# A single DDEV project is created once for the whole file (setup_file) to keep
# the suite fast. Individual tests create/remove config overrides as needed.
#
# Run: bats tests/fixtures.bats

load helpers

setup_file() {
  set -eu -o pipefail

  export PROJNAME="test-module-developer-fixtures"
  export TESTDIR="${HOME}/tmp/bats-ddev/${PROJNAME}"
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
  ddev config --project-type=drupal --project-name="${PROJNAME}" --docroot=web
  ddev add-on get "${DIR}"
  ddev start -y

  # Stage fixture modules and the phpcompat test file once for all tests.
  copy_fixture dirty_module
  copy_fixture clean_module
  mkdir -p "${TESTDIR}/web/modules/custom"
  cp "${BATS_TEST_DIRNAME}/testdata/phpcompat_bad.php" "${TESTDIR}/phpcompat_bad.php"

  # rector targets web/modules/custom; ensure the directory exists.
  mkdir -p "${TESTDIR}/web/modules/custom"
}

teardown_file() {
  cd "${TESTDIR}" || true
  ddev delete -Oy || true
}

setup() {
  cd "${TESTDIR}"
  # Remove any project-level config overrides that could leak between tests.
  rm -f phpcs.xml phpcs.xml.dist .phpcs.xml phpstan.neon phpstan.neon.dist \
        .stylelintrc.json .eslintrc.json rector.php .gitlab-ci.yml
}

teardown() {
  rm -f phpcs.xml phpcs.xml.dist .phpcs.xml phpstan.neon phpstan.neon.dist \
        .stylelintrc.json .eslintrc.json rector.php .cspell.json .cspell.json.bak \
        .gitlab-ci.yml
}

# ---------------------------------------------------------------------------
# phpcs
# ---------------------------------------------------------------------------

@test "phpcs: detects violations in dirty_module and exits 1" {
  run ddev phpcs web/modules/custom/dirty_module
  assert_failure
  assert_output --partial "ERROR"
}

@test "phpcs: clean_module passes all Drupal coding standards and exits 0" {
  run ddev phpcs web/modules/custom/clean_module
  assert_success
}

# ---------------------------------------------------------------------------
# phpcbf
# ---------------------------------------------------------------------------

@test "phpcbf: runs without a fatal configuration error on dirty_module" {
  # phpcbf exits 0 (all fixed) or 1 (some fixed, remaining violations).
  # Exit 2+ means a fatal configuration error.
  run ddev phpcbf web/modules/custom/dirty_module
  [ "${status}" -le 1 ]
}

# ---------------------------------------------------------------------------
# phpmd
# ---------------------------------------------------------------------------

@test "phpmd: no arguments prints Usage and exits 1" {
  run ddev phpmd
  assert_failure
  assert_output --partial "Usage:"
}

@test "phpmd: detects unused local variable in BadClass.php and exits non-zero" {
  run ddev phpmd web/modules/custom/dirty_module/src/BadClass.php text
  assert_failure
}

@test "phpmd: clean_module passes all rules and exits 0" {
  run ddev phpmd web/modules/custom/clean_module text
  assert_success
}

# ---------------------------------------------------------------------------
# stylelint
# ---------------------------------------------------------------------------

@test "stylelint: detects invalid hex color in bad.css and exits non-zero" {
  run ddev stylelint "web/modules/custom/dirty_module/css/bad.css"
  assert_failure
  assert_output --partial "bad.css"
}

@test "stylelint: clean CSS passes and exits 0" {
  run ddev stylelint "web/modules/custom/clean_module/css/good.css"
  assert_success
}

@test "stylelint: --fix flag is accepted without a configuration crash" {
  # --fix exits 0 (all fixed) or 1 (unfixable violations remain); 78 = config error.
  run ddev stylelint --fix "web/modules/custom/dirty_module/css/bad.css"
  [ "${status}" -le 2 ]
}

# ---------------------------------------------------------------------------
# eslint
# ---------------------------------------------------------------------------

@test "eslint: detects prettier double-quote violation in bad.js and exits non-zero" {
  run ddev eslint web/modules/custom/dirty_module/js/bad.js
  assert_failure
}

@test "eslint: clean JS passes and exits 0" {
  run ddev eslint web/modules/custom/clean_module/js/good.js
  assert_success
}

# ---------------------------------------------------------------------------
# cspell
# ---------------------------------------------------------------------------

@test "cspell: detects misspelling 'speling' in README.md and exits non-zero" {
  run ddev cspell web/modules/custom/dirty_module/README.md
  assert_failure
  assert_output --partial "speling"
}

@test "cspell: clean PHP file passes and exits 0" {
  run ddev cspell web/modules/custom/clean_module/clean_module.module
  assert_success
}

# ---------------------------------------------------------------------------
# phpcompat
# ---------------------------------------------------------------------------

@test "phpcompat: detects each() (removed in PHP 8.0) and exits non-zero" {
  run ddev phpcompat phpcompat_bad.php
  assert_failure
}

@test "phpcompat: clean_module PHP passes PHP 8.2 compatibility check and exits 0" {
  run ddev phpcompat web/modules/custom/clean_module
  assert_success
}

# ---------------------------------------------------------------------------
# phpstan (smoke tests — full analysis requires a Drupal installation)
# ---------------------------------------------------------------------------

@test "phpstan: --version exits 0 and prints PHPStan" {
  run ddev phpstan --version
  assert_success
  assert_output --partial "PHPStan"
}

@test "phpstan: temp neon files are removed after execution" {
  # Run an analysis (will likely fail due to missing vendor, that's fine).
  ddev phpstan web/modules/custom/clean_module || true
  # No temp neon files should remain regardless of the analysis outcome.
  run ddev exec "ls /tmp/phpstan-*.neon 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

# ---------------------------------------------------------------------------
# rector (smoke tests — full analysis requires Drupal upgrade sets)
# ---------------------------------------------------------------------------

@test "rector: binary executes and --version exits 0" {
  # The auto-generated config requires palantirnet/drupal-rector to be resolvable
  # from the global autoloader, which is not guaranteed without a project vendor.
  # Test the binary directly to verify it is installed and runnable.
  run ddev exec "rector --version"
  assert_success
  assert_output --partial "Rector"
}

@test "rector: temp config file is removed after execution" {
  ddev rector process --dry-run || true
  run ddev exec "ls /tmp/rector-*.php 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

# ---------------------------------------------------------------------------
# phpunit (smoke tests — functional tests require a full Drupal installation)
# ---------------------------------------------------------------------------

@test "phpunit: exits with a clear message when Drupal bootstrap is not installed" {
  run ddev phpunit
  assert_failure
  assert_output --partial "bootstrap"
}

# ---------------------------------------------------------------------------
# parallel-lint
# ---------------------------------------------------------------------------

@test "parallel-lint: exits 0 with a helpful message when binary is not installed" {
  # Covers the graceful-degradation path. Skipped once the image is rebuilt.
  if ddev exec "command -v parallel-lint" >/dev/null 2>&1; then
    skip "parallel-lint is installed; this test covers the not-installed path only"
  fi
  run ddev parallel-lint web/modules/custom/clean_module
  assert_success
  assert_output --partial "not installed"
}

@test "parallel-lint: --version exits 0 when binary is installed" {
  if ! ddev exec "command -v parallel-lint" >/dev/null 2>&1; then
    skip "parallel-lint not yet installed; run 'ddev restart' to rebuild the web container"
  fi
  run ddev exec "parallel-lint --version"
  assert_success
}

@test "parallel-lint: clean_module passes PHP syntax check when binary is installed" {
  if ! ddev exec "command -v parallel-lint" >/dev/null 2>&1; then
    skip "parallel-lint not yet installed; run 'ddev restart' to rebuild the web container"
  fi
  run ddev parallel-lint web/modules/custom/clean_module
  assert_success
}

@test "parallel-lint: detects syntax error in bad_syntax.php when binary is installed" {
  if ! ddev exec "command -v parallel-lint" >/dev/null 2>&1; then
    skip "parallel-lint not yet installed; run 'ddev restart' to rebuild the web container"
  fi
  cp "${BATS_TEST_DIRNAME}/testdata/bad_syntax.php" "${TESTDIR}/bad_syntax.php"
  run ddev parallel-lint bad_syntax.php
  assert_failure
}

# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

@test "checks: exits 0 on clean_module when all applicable CI checks pass" {
  # PHPStan requires vendor/autoload.php which is absent in this bare test
  # project; skip it so the remaining CI checks exercise the pass path cleanly.
  cat > .gitlab-ci.yml <<'YAML'
variables:
  SKIP_PHPSTAN: "1"
YAML
  run ddev checks web/modules/custom/clean_module
  assert_success
  assert_output --partial "Result: passed"
}

@test "checks: exits 1 on dirty_module when CI checks fail" {
  run ddev checks web/modules/custom/dirty_module
  assert_failure
  assert_output --partial "Result: FAILED"
}

@test "checks: --bonus flag includes phpmd and phpcompat in output" {
  run ddev checks --bonus web/modules/custom/dirty_module
  assert_failure
  assert_output --partial "PHP Mess Detector"
  assert_output --partial "PHP Compatibility"
}

@test "checks: phpunit is skipped automatically when Drupal bootstrap is absent" {
  cat > .gitlab-ci.yml <<'YAML'
variables:
  SKIP_PHPSTAN: "1"
YAML
  run ddev checks web/modules/custom/clean_module
  assert_output --partial "PHPUnit"
  assert_output --partial "skipped"
}

# ---------------------------------------------------------------------------
# checks-fixes
# ---------------------------------------------------------------------------

@test "checks-fixes: exits 0 on clean_module with all three fixers passing" {
  run ddev checks-fixes web/modules/custom/clean_module
  assert_success
  assert_output --partial "PHP Code Beautifier and Fixer"
  assert_output --partial "ESLint"
  assert_output --partial "Stylelint"
  assert_output --partial "Result: passed"
}

@test "checks-fixes: exits 1 on dirty_module when unfixable violations remain" {
  # Use a throwaway copy so phpcbf/eslint --fix/stylelint --fix don't corrupt
  # dirty_module for the other tests that rely on it staying dirty.
  copy_fixture dirty_module dirty_module_fixes
  run ddev checks-fixes web/modules/custom/dirty_module_fixes
  assert_failure
  assert_output --partial "PHP Code Beautifier and Fixer"
  assert_output --partial "ESLint"
  assert_output --partial "Stylelint"
  assert_output --partial "Result: FAILED"
  remove_fixture dirty_module_fixes
}
