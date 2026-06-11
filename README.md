[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/mandclu/ddev-module-developer/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/mandclu/ddev-module-developer/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/mandclu/ddev-module-developer)](https://github.com/mandclu/ddev-module-developer/commits)
[![release](https://img.shields.io/github/v/release/mandclu/ddev-module-developer)](https://github.com/mandclu/ddev-module-developer/releases/latest)

# DDEV Module Developer

DDEV add-on providing code quality validation commands for Drupal module development. The commands and their default configurations [match the Drupal GitLab CI template](https://www.drupal.org/project/gitlab_templates) from the Drupal Association, so code that passes locally will pass in CI.

All tools are installed at container build time — they are available immediately after `ddev restart` with no per-start installation overhead.


## Install

1. If you haven't already, [install Docker and DDEV](https://ddev.readthedocs.io/en/stable/users/install/).
2. Set up a Drupal project with DDEV, either by following the [Drupal CMS quickstart](https://docs.ddev.com/en/stable/users/quickstart/#drupal-drupal-cms) or the [Drupal core quickstart](https://docs.ddev.com/en/stable/users/quickstart/#drupal).
3. Add this add-on and restart:

```sh
ddev add-on get mandclu/ddev-module-developer
ddev restart
```

4. Optional — for `eslint` and `stylelint` to use Drupal core's own configuration files (the same ones used in CI), install core's JavaScript dependencies:

```sh
ddev exec "cd web/core && yarn install"
```

Without this step both commands still work using the bundled fallback configurations.


## Commands

This add-on provides the following DDEV commands, all running inside the web container.

- `ddev checks` — Run all Drupal GitLab CI checks in sequence and print a summary. See [Running all checks](#running-all-checks) below.
- `ddev parallel-lint` — Run [php-parallel-lint](https://github.com/php-parallel-lint/php-parallel-lint) to check PHP files for syntax errors.
- `ddev phpcs` — Run [PHP_CodeSniffer](https://github.com/PHPCSStandards/PHP_CodeSniffer) against Drupal coding standards.
- `ddev phpcbf` — Auto-fix phpcs violations using PHP Code Beautifier and Fixer.
- `ddev phpstan` — Run [PHPStan](https://phpstan.org) static analysis with the Drupal extension.
- `ddev phpmd` — Run [PHP Mess Detector](https://phpmd.org).
- `ddev rector` — Run [Drupal Rector](https://github.com/palantirnet/drupal-rector) to find and fix deprecated API usage.
- `ddev phpunit` — Run [PHPUnit](https://phpunit.de) tests.
- `ddev stylelint` — Run [Stylelint](https://stylelint.io) on CSS/SCSS files.
- `ddev eslint` — Run [ESLint](https://eslint.org) on JavaScript and YAML files, with Prettier formatting checks.
- `ddev cspell` — Run [CSpell](https://cspell.org) spell-checking across project files.

Pass a path as the first argument to any command to target a specific file or directory:

```sh
ddev checks web/modules/custom/mymodule
ddev parallel-lint web/modules/custom/mymodule
ddev phpcs web/modules/custom/mymodule
ddev phpstan analyse web/modules/custom/mymodule
ddev phpunit web/modules/custom/mymodule
ddev stylelint 'web/modules/custom/mymodule/**/*.css'
ddev eslint web/modules/custom/mymodule/js
ddev phpmd web/modules/custom/mymodule text
```

Run without a path argument from inside a module directory to target that module:

```sh
cd web/modules/custom/mymodule
ddev checks
ddev phpcs
ddev phpunit
```


## Running all checks

`ddev checks` runs the same sequence of code quality jobs that the [Drupal GitLab Templates](https://www.drupal.org/project/gitlab_templates) pipeline runs, in the same order:

1. **PHP Lint** (`parallel-lint`) — fast syntax check; catches parse errors before heavier tools run.
2. **PHP CodeSniffer** — Drupal coding standards.
3. **PHPStan** — static analysis.
4. **ESLint** — JavaScript and YAML formatting.
5. **Stylelint** — CSS/SCSS validation.
6. **CSpell** — spell checking.
7. **PHPUnit** — unit and functional tests, but only when all preceding checks pass and the Drupal test bootstrap is installed. Automatically skipped otherwise.

Each tool prints its normal output inline. At the end, a summary shows the result for every check:

```
══════════════════════════════════════════════════════
  ✓  PHP Lint
  ✓  PHP CodeSniffer
  ✓  PHPStan
  ✓  ESLint
  ✓  Stylelint
  ✓  CSpell
  -  PHPUnit  (skipped — Drupal test bootstrap not installed)

Result: passed  (1 skipped, 6 passed)
```

`ddev checks` exits 0 when all checks pass and 1 when any check fails.


### Bonus checks

Pass `--bonus` to also run checks that are not part of the Drupal GitLab CI pipeline but are available in this add-on:

```sh
ddev checks --bonus
ddev checks --bonus web/modules/custom/mymodule
```

Bonus checks run after the CI checks and do not affect the phpunit gate. They are treated as hard failures (no `allow_failure` equivalent):

- **PHP Mess Detector** — code quality and complexity metrics.
- **PHP Compatibility** — detects PHP version compatibility issues.


### Warnings and allow_failure

Some projects configure certain CI jobs to allow failure (for example, during a transition period). This add-on respects the same variables the Drupal GitLab CI pipeline uses. Set them in the `variables:` block of your `.gitlab-ci.yml`:

| Variable | Effect |
|---|---|
| `_ALL_VALIDATE_ALLOW_FAILURE: "1"` | All CI validation checks show failures as warnings |
| `_PHPCS_ALLOW_FAILURE: "1"` | phpcs failures show as warnings |
| `_PHPSTAN_ALLOW_FAILURE: "1"` | phpstan failures show as warnings |
| `_ESLINT_ALLOW_FAILURE: "1"` | eslint failures show as warnings |
| `_STYLELINT_ALLOW_FAILURE: "1"` | stylelint failures show as warnings |
| `_CSPELL_ALLOW_FAILURE: "1"` | cspell failures show as warnings |
| `_PHPUNIT_ALLOW_FAILURE: "1"` | phpunit failures show as warnings |

When a check is configured to allow failure and it fails, it shows as `⚠` in the summary. If every failure was a warning (no hard failures), `ddev checks` exits 0 with `Result: passed with warnings`.

Per-tool variables take precedence over `_ALL_VALIDATE_ALLOW_FAILURE`, matching how GitLab CI applies these settings.


### Skipping checks

`ddev checks` also respects `SKIP_*` variables from `.gitlab-ci.yml`. A skipped check is shown as `-` in the summary and does not affect the exit status:

| Variable | Effect |
|---|---|
| `SKIP_COMPOSER_LINT: "1"` | Skips `parallel-lint` |
| `SKIP_PHPCS: "1"` | Skips `phpcs` |
| `SKIP_PHPSTAN: "1"` | Skips `phpstan` |
| `SKIP_ESLINT: "1"` | Skips `eslint` |
| `SKIP_STYLELINT: "1"` | Skips `stylelint` |
| `SKIP_CSPELL: "1"` | Skips `cspell` |
| `SKIP_PHPUNIT: "1"` | Skips `phpunit` |

### PHPUnit prerequisites

`ddev phpunit` requires `drupal/core-dev` to be installed in your project. If it is not already present, add it with:

```sh
ddev composer require --dev drupal/core-dev -W
```

The `-W` flag (`--with-all-dependencies`) is needed to allow Composer to adjust the versions of shared packages (such as `sebastian/diff`) to satisfy `phpunit`'s constraints alongside those of `drupal/core`.

If your project has a `phpunit.xml` or `phpunit.xml.dist` in the project root, `ddev phpunit` uses it as-is. Without one, the command bootstraps from `web/core/tests/bootstrap.php` and sets the following DDEV-standard defaults so all test types work out of the box:

| Environment variable             | Default value                               |
| -------------------------------- | ------------------------------------------- |
| `SIMPLETEST_BASE_URL`            | `$DDEV_PRIMARY_URL`                         |
| `SIMPLETEST_DB`                  | `mysql://db:db@db/db`                       |
| `BROWSERTEST_OUTPUT_DIRECTORY`   | `web/sites/simpletest/browser_output`       |

Override any of these by setting them in `.ddev/config.yaml` under `web_environment` before running the command.

By default, `ddev phpunit` passes `--display-all-issues` to PHPUnit so that deprecations, notices, and warnings are shown inline rather than summarised. To suppress this output, set `PHPUNIT_DISPLAY_ALL_ISSUES=0` in `.ddev/config.yaml`:

```yaml
web_environment:
  - PHPUNIT_DISPLAY_ALL_ISSUES=0
```


## Configuration

Each command follows a three-level priority for its configuration:

1. **Project config** — if a config file exists in your project root (e.g. `phpcs.xml`, `phpstan.neon`, `.stylelintrc.json`), it is used as-is.
2. **Drupal core config** — for `eslint` and `stylelint`, if `core/node_modules` is installed, the command uses `core/.eslintrc.passing.json` and `core/.stylelintrc.json` respectively — the same files used in the GitLab CI pipeline.
3. **Bundled defaults** — if neither of the above is found, the add-on's own default configs in `.ddev/module-developer/config/` are used. These match the [Drupal GitLab Templates](https://www.drupal.org/project/gitlab_templates) defaults.

### Overriding a tool's configuration

Place a config file in your project root to override the bundled default for any tool:

| Tool           | Config file(s)                                                                              |
| -------------- | ------------------------------------------------------------------------------------------- |
| phpcs / phpcbf | `phpcs.xml` or `phpcs.xml.dist`                                                             |
| phpstan        | `phpstan.neon` or `phpstan.neon.dist`                                                       |
| rector         | `rector.php` or `rector.php.dist`                                                           |
| stylelint      | `.stylelintrc.json` (or any [supported format](https://stylelint.io/user-guide/configure/)) |
| eslint         | `.eslintrc.json` (or any [supported format](https://eslint.org/docs/latest/use/configure/)) |
| cspell         | `.cspell.json`                                                                              |

The bundled `phpcs.xml` matches the [GitLab Templates default](https://git.drupalcode.org/project/gitlab_templates/-/blob/main/assets/phpcs.xml.dist): only the `Drupal` standard is enforced; `DrupalPractice` is commented out and can be enabled if required.

The bundled `phpstan.neon` runs at level 0, matching the GitLab Templates default. To raise the level, add a `phpstan.neon` to your project root:

```neon
parameters:
  level: 2
```

### PHPStan and the Drupal extension

The Drupal GitLab CI Docker image pre-installs `mglaman/phpstan-drupal`, so the template's `phpstan.neon` does not reference it. In DDEV there is no such pre-built image, so when no project-level config is found the `phpstan` command automatically injects the extension. If you supply your own `phpstan.neon` and want the Drupal extension, add the includes explicitly:

```neon
includes:
  - /usr/local/composer/vendor/mglaman/phpstan-drupal/extension.neon
  - /usr/local/composer/vendor/mglaman/phpstan-drupal/rules.neon
```

### Ignoring files

Most tools support an ignore file in the project root:

- phpcs: `<exclude-pattern>` entries in your `phpcs.xml`
- stylelint: `.stylelintignore`
- eslint: `.eslintignore`
- cspell: `ignorePaths` in `.cspell.json`


## Automatically fix coding standard violations

`ddev stylelint --fix` and `ddev eslint --fix` will auto-fix Prettier formatting issues in CSS and JavaScript files respectively:

```sh
ddev stylelint --fix
ddev stylelint --fix 'web/modules/custom/mymodule/**/*.css'
ddev eslint --fix
ddev eslint --fix web/modules/custom/mymodule/js
```

Set up a pre-commit hook that runs `phpcbf` before every commit:

1. Create `.git/hooks/pre-commit` if it does not already exist.
2. Add the following:

```bash
#!/usr/bin/env bash
ddev phpcbf -q
```

3. Make it executable: `chmod +x .git/hooks/pre-commit`.


## Troubleshooting

**"Error: unknown command"**

Commands are only available when the DDEV project type is `drupal`. Confirm the type in `.ddev/config.yaml`:

```yaml
type: drupal
```

> [!TIP]
> Run `ddev restart` after editing `.ddev/config.yaml`.

**ESLint or Stylelint reports missing plugin errors**

The bundled fallback configs use globally installed plugins. If you are pointing ESLint or Stylelint at a custom config that references plugins not installed globally, either install those plugins inside the container or add them to your project's `package.json` and run `yarn install` / `npm install`.

**PHPStan cannot find Drupal classes**

Make sure `drupal_root` is set correctly. When using the bundled config the `phpstan` command sets this automatically from `$DDEV_DOCROOT`. If you supply your own `phpstan.neon`, add:

```neon
parameters:
  drupal:
    drupal_root: /var/www/html/web
```

Adjust the path to match your project's docroot.


## Contributing

Tests are written in [Bats](https://bats-core.readthedocs.io/en/stable/). Install the test helper submodules first:

```bash
git submodule update --init
```

Then run the tests from the project root:

```bash
./tests/bats/bin/bats ./tests
```

Tests are triggered automatically on every push and run nightly. Contributions and bug reports are welcome.


## Credits

Contributed and maintained by Martin Anderson-Clutz ([@mandclu](https://github.com/mandclu)).
