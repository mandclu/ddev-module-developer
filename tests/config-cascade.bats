#!/usr/bin/env bats

# Config precedence tests: project-level config must override bundled defaults.
#
# A single DDEV project is shared across all tests in this file (setup_file).
# Each test creates config overrides in the project root and teardown() removes
# them so subsequent tests start clean.
#
# Run: bats tests/config-cascade.bats

load helpers

setup_file() {
  set -eu -o pipefail

  export PROJNAME="test-module-developer-cascade"
  export TESTDIR="${HOME}/tmp/bats-ddev/${PROJNAME}"
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

  mkdir -p "${TESTDIR}"
  cd "${TESTDIR}"
  ddev config --project-type=drupal --project-name="${PROJNAME}" --docroot=web
  ddev add-on get "${DIR}"
  ddev start -y

  copy_fixture dirty_module
  copy_fixture clean_module
}

teardown_file() {
  cd "${TESTDIR}" || true
  ddev delete -Oy || true
}

setup() {
  cd "${TESTDIR}"
  # Start each test with no project-level config overrides.
  rm -f phpcs.xml phpcs.xml.dist .phpcs.xml phpstan.neon phpstan.neon.dist \
        phpstan.dist.neon .stylelintrc.json .eslintrc.json rector.php
}

teardown() {
  rm -f phpcs.xml phpcs.xml.dist .phpcs.xml phpstan.neon phpstan.neon.dist \
        phpstan.dist.neon .stylelintrc.json .eslintrc.json rector.php custom-rules.xml \
        .cspell.json .cspell.json.bak
}

# ---------------------------------------------------------------------------
# phpcs
# ---------------------------------------------------------------------------

@test "phpcs: project phpcs.xml is used and phpcs.xml.dist is not downloaded" {
  cat > phpcs.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="Test-PSR12">
  <rule ref="PSR12"/>
</ruleset>
XML
  # Run phpcs so it has a chance to download the config — it must not when a
  # project phpcs.xml already exists.
  ddev phpcs web/modules/custom/clean_module || true
  [ ! -f phpcs.xml.dist ]
}

@test "phpcs: without project config, phpcs.xml.dist is downloaded from GitLab Templates" {
  run ddev phpcs web/modules/custom/clean_module
  assert_success
  [ -f phpcs.xml.dist ]
}

# ---------------------------------------------------------------------------
# phpcbf
# ---------------------------------------------------------------------------

@test "phpcbf: project phpcs.xml is respected instead of downloading phpcs.xml.dist" {
  cat > phpcs.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="Test-PSR12">
  <rule ref="PSR12"/>
</ruleset>
XML
  ddev phpcbf web/modules/custom/clean_module || true
  [ ! -f phpcs.xml.dist ]
}

# ---------------------------------------------------------------------------
# phpstan
# ---------------------------------------------------------------------------

@test "phpstan: project-level phpstan.neon is used when present at project root" {
  cat > phpstan.neon <<'NEON'
parameters:
  level: 0
NEON
  # With a project neon, phpstan should exec without building a temp neon.
  run ddev phpstan --version
  assert_success
}

@test "phpstan: temp neon is cleaned up even when a project neon is NOT present" {
  # Run phpstan (analysis will likely fail without a Drupal vendor, that is fine).
  ddev phpstan web/modules/custom/clean_module || true
  run ddev exec "ls /tmp/phpstan-*.neon 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}

# ---------------------------------------------------------------------------
# phpmd
# ---------------------------------------------------------------------------

@test "phpmd: custom ruleset XML is accepted as the third argument" {
  cat > custom-rules.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="Custom" xmlns="http://pmd.sf.net/ruleset/1.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://pmd.sf.net/ruleset/1.0.0 http://pmd.sf.net/ruleset_xml_schema.xsd">
  <description>Minimal custom ruleset for testing</description>
  <rule ref="rulesets/naming.xml/LongClassName"/>
</ruleset>
XML
  # Should run without "ruleset not found" error (exit 0 = no violations).
  run ddev phpmd web/modules/custom/clean_module text custom-rules.xml
  assert_success
}

# ---------------------------------------------------------------------------
# stylelint
# ---------------------------------------------------------------------------

@test "stylelint: project .stylelintrc.json overrides bundled config" {
  # Empty rules — even the invalid hex color passes.
  cat > .stylelintrc.json <<'JSON'
{"rules": {}}
JSON
  run ddev stylelint "web/modules/custom/dirty_module/css/bad.css"
  assert_success
}

@test "stylelint: without project config, bundled default flags bad.css" {
  run ddev stylelint "web/modules/custom/dirty_module/css/bad.css"
  assert_failure
}

# ---------------------------------------------------------------------------
# eslint
# ---------------------------------------------------------------------------

@test "eslint: project .eslintrc.json overrides bundled config" {
  # No rules — the double-quote violation passes.
  cat > .eslintrc.json <<'JSON'
{"rules": {}}
JSON
  run ddev eslint web/modules/custom/dirty_module/js/bad.js
  assert_success
}

@test "eslint: without project config, bundled default flags bad.js" {
  run ddev eslint web/modules/custom/dirty_module/js/bad.js
  assert_failure
}

# ---------------------------------------------------------------------------
# rector
# ---------------------------------------------------------------------------

@test "rector: project rector.php is used when present" {
  # Write a minimal config that targets an empty path so rector exits cleanly.
  cat > rector.php <<'PHP'
<?php
use Rector\Config\RectorConfig;
return RectorConfig::configure()->withPaths([]);
PHP
  run ddev rector process --dry-run
  assert_success
}

@test "rector: temp rector.php is cleaned up after execution without project config" {
  ddev rector process --dry-run || true
  run ddev exec "ls /tmp/rector-*.php 2>/dev/null | wc -l | tr -d ' '"
  assert_output "0"
}
