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

- `ddev phpcs` — Run [PHP_CodeSniffer](https://github.com/PHPCSStandards/PHP_CodeSniffer) against Drupal coding standards.
- `ddev phpcbf` — Auto-fix phpcs violations using PHP Code Beautifier and Fixer.
- `ddev phpstan` — Run [PHPStan](https://phpstan.org) static analysis with the Drupal extension.
- `ddev phpmd` — Run [PHP Mess Detector](https://phpmd.org).
- `ddev rector` — Run [Drupal Rector](https://github.com/palantirnet/drupal-rector) to find and fix deprecated API usage.
- `ddev stylelint` — Run [Stylelint](https://stylelint.io) on CSS/SCSS files.
- `ddev eslint` — Run [ESLint](https://eslint.org) on JavaScript and YAML files, with Prettier formatting checks.
- `ddev cspell` — Run [CSpell](https://cspell.org) spell-checking across project files.

Pass a path as the first argument to any command to target a specific file or directory:

```sh
ddev phpcs web/modules/custom/mymodule
ddev phpstan analyse web/modules/custom/mymodule
ddev stylelint 'web/modules/custom/mymodule/**/*.css'
ddev eslint web/modules/custom/mymodule/js
ddev phpmd web/modules/custom/mymodule text
```

Run without a path argument to use each tool's own default discovery (where supported).


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
