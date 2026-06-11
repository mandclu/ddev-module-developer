#!/usr/bin/env bats

# Binary precedence tests: project-local binaries must win over global binaries.
#
# A single DDEV project is shared across all tests. Each test creates tiny
# executable shims in vendor/bin, node_modules/.bin, or web/core/node_modules/.bin
# and asserts the wrapper command invokes the expected shim.

load helpers

setup_file() {
  set -eu -o pipefail

  export PROJNAME="test-module-developer-binaries"
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
  rm -rf vendor node_modules web/core
  rm -f phpcs.xml phpcs.xml.dist .phpcs.xml phpstan.neon phpstan.neon.dist \
        phpstan.dist.neon rector.php rector.php.dist phpunit.xml phpunit.xml.dist \
        .eslintrc.json .stylelintrc.json
}

teardown() {
  rm -rf vendor node_modules web/core
  rm -f phpcs.xml phpcs.xml.dist .phpcs.xml phpstan.neon phpstan.neon.dist \
        phpstan.dist.neon rector.php rector.php.dist phpunit.xml phpunit.xml.dist \
        .eslintrc.json .stylelintrc.json
}

@test "phpcs: project vendor/bin binary takes precedence" {
  make_shim vendor/bin/phpcs LOCAL_PHPCS
  cat > phpcs.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="Test"/>
XML

  run ddev phpcs web/modules/custom/clean_module
  assert_success
  assert_output --partial "LOCAL_PHPCS"
  assert_output --partial "ARGS:-s web/modules/custom/clean_module"
}

@test "phpcbf: project vendor/bin binary takes precedence" {
  make_shim vendor/bin/phpcbf LOCAL_PHPCBF
  cat > phpcs.xml <<'XML'
<?xml version="1.0"?>
<ruleset name="Test"/>
XML

  run ddev phpcbf web/modules/custom/clean_module
  assert_success
  assert_output --partial "LOCAL_PHPCBF"
  assert_output --partial "ARGS:web/modules/custom/clean_module"
}

@test "phpmd: project vendor/bin binary takes precedence" {
  make_shim vendor/bin/phpmd LOCAL_PHPMD

  run ddev phpmd web/modules/custom/clean_module text
  assert_success
  assert_output --partial "LOCAL_PHPMD"
  assert_output --partial "ARGS:web/modules/custom/clean_module text /mnt/ddev_config/module-developer/config/phpmd-ruleset.xml"
}

@test "phpstan: project vendor/bin binary takes precedence" {
  make_shim vendor/bin/phpstan LOCAL_PHPSTAN
  cat > phpstan.neon <<'NEON'
parameters:
  level: 0
NEON

  run ddev phpstan --version
  assert_success
  assert_output --partial "LOCAL_PHPSTAN"
  assert_output --partial "ARGS:--version"
}

@test "rector: project vendor/bin binary takes precedence" {
  make_shim vendor/bin/rector LOCAL_RECTOR
  cat > rector.php <<'PHP'
<?php
return Rector\Config\RectorConfig::configure()->withPaths([]);
PHP

  run ddev rector process --dry-run
  assert_success
  assert_output --partial "LOCAL_RECTOR"
  assert_output --partial "ARGS:process --dry-run --config=/var/www/html/rector.php"
}

@test "phpunit: project vendor/bin binary takes precedence" {
  make_shim vendor/bin/phpunit LOCAL_PHPUNIT
  cat > phpunit.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit/>
XML

  run ddev phpunit --colors=never
  assert_success
  assert_output --partial "LOCAL_PHPUNIT"
  assert_output --partial "ARGS:--colors=never"
}

@test "eslint: web/core node_modules binary takes precedence over project node_modules" {
  make_shim web/core/node_modules/.bin/eslint CORE_ESLINT
  make_shim node_modules/.bin/eslint PROJECT_ESLINT
  cat > .eslintrc.json <<'JSON'
{"rules": {}}
JSON

  run ddev eslint web/modules/custom/clean_module/js/good.js
  assert_success
  assert_output --partial "CORE_ESLINT"
  refute_output --partial "PROJECT_ESLINT"
}

@test "eslint: project node_modules binary is used when core binary is absent" {
  make_shim node_modules/.bin/eslint PROJECT_ESLINT
  cat > .eslintrc.json <<'JSON'
{"rules": {}}
JSON

  run ddev eslint web/modules/custom/clean_module/js/good.js
  assert_success
  assert_output --partial "PROJECT_ESLINT"
}

@test "stylelint: web/core node_modules binary takes precedence over project node_modules" {
  make_shim web/core/node_modules/.bin/stylelint CORE_STYLELINT
  make_shim node_modules/.bin/stylelint PROJECT_STYLELINT

  run ddev stylelint --version
  assert_success
  assert_output --partial "CORE_STYLELINT"
  refute_output --partial "PROJECT_STYLELINT"
}

@test "stylelint: project node_modules binary is used when core binary is absent" {
  make_shim node_modules/.bin/stylelint PROJECT_STYLELINT

  run ddev stylelint --version
  assert_success
  assert_output --partial "PROJECT_STYLELINT"
}
