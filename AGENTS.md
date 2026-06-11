# AGENTS.md — ddev-module-developer

## Purpose

This DDEV add-on lets Drupal module developers run the same code-quality validators
locally that the [Drupal GitLab CI templates](https://www.drupal.org/project/gitlab_templates)
run in CI. The goal is parity: code that passes locally must pass in the pipeline,
and failures in the pipeline should be reproducible locally.

A developer should be able to `cd` into their module directory inside a DDEV-managed
Drupal project and run `ddev phpcs`, `ddev phpstan`, etc. with no extra setup.


## Repository layout

```
commands/web/       # DDEV web-container commands (one file per tool)
module-developer/
  config/           # Bundled default configs for each tool
  lib/              # Shared bash helpers sourced by the commands
web-build/
  Dockerfile        # Installs all tools at container-build time
install.yaml        # DDEV add-on manifest
tests/test.bats     # Bats integration tests
```


## Commands

Each file in `commands/web/` is a bash script that DDEV injects as a `ddev <name>`
command running inside the web container.

| Command      | Tool                          | Language |
| ------------ | ----------------------------- | -------- |
| `phpcs`      | PHP_CodeSniffer               | PHP      |
| `phpcbf`     | PHP Code Beautifier and Fixer  | PHP      |
| `phpstan`    | PHPStan + mglaman/phpstan-drupal | PHP   |
| `phpmd`      | PHP Mess Detector             | PHP      |
| `rector`     | Drupal Rector                 | PHP      |
| `phpcompat`  | PHP compatibility checker     | PHP      |
| `stylelint`  | Stylelint                     | CSS/SCSS |
| `eslint`     | ESLint + Prettier + yml plugin | JS/YAML |
| `cspell`     | CSpell                        | all      |

All PHP tools are installed globally via Composer into `/usr/local/composer/` and
symlinked into `/usr/local/bin/`. Node.js tools are installed globally via npm.
Everything is installed at image-build time (in `web-build/Dockerfile`) so there is
no per-start installation overhead.


## How each command script works

Every command script follows the same three-step pattern:

### 1. Resolve the binary

Prefer the project-local binary over the global one, matching how Drupal CI uses
`$COMPOSER_BIN_DIR`:

```bash
PHPCS="${DDEV_APPROOT}/vendor/bin/phpcs"
if [ ! -x "${PHPCS}" ]; then
  PHPCS="phpcs"
fi
```

For Node.js tools, check `node_modules/.bin/` first:

```bash
ESLINT="${DDEV_APPROOT}/node_modules/.bin/eslint"
if [ ! -x "${ESLINT}" ]; then
  ESLINT="eslint"
fi
```

### 1b. Normalize absolute host-path arguments

After resolving the binary and before any defaulting or `exec`, every command
sources the shared helper and rewrites its positional arguments:

```bash
# shellcheck source=../../module-developer/lib/host-paths.sh
source /mnt/ddev_config/module-developer/lib/host-paths.sh
ddev_normalize_host_paths "$@"
set -- "${DDEV_NORMALIZED_ARGS[@]}"
```

`HostWorkingDir: true` only maps the *current directory* into the container;
arguments are passed through verbatim. `ddev_normalize_host_paths`
(`module-developer/lib/host-paths.sh`) converts an absolute *host* path argument
to its in-container equivalent by stripping leading components until the remainder
resolves under `${DDEV_APPROOT}`. This lets IDE external tools and agents pass full
host paths. It is a no-op for relative paths, flags, already-in-container paths, and
unresolvable paths. The helper must run **before** the no-path default so the
default and config-resolution logic see container paths.

### 2. Default to the current directory when no path is given

Commands that accept a bare path argument (e.g. `phpcs`, `phpcbf`) default to `.`
when called with no arguments. DDEV maps the host's current working directory into
the container via `## HostWorkingDir: true`, so `ddev phpcs` run from inside a module
directory scans exactly that module — the same behaviour as CI passing
`$DRUPAL_PROJECT_FOLDER`:

```bash
if [ "$#" -eq 0 ]; then
  set -- .
fi
```

Commands that use subcommands (`phpstan`, `rector`) or require explicit positional
arguments (`phpmd`) handle their own argument defaulting separately.

### 3. Resolve configuration (three-level priority)

1. **Project config** — if a recognised config file exists at `$DDEV_APPROOT`
   (e.g. `phpcs.xml`, `phpstan.neon`, `.stylelintrc.json`), use it as-is and
   exec immediately.
2. **Drupal core config** — for `eslint` and `stylelint` only: if
   `web/core/node_modules` is installed, use `core/.eslintrc.passing.json` /
   `core/.stylelintrc.json` — the exact files Drupal CI uses.
3. **Bundled defaults** — fall back to the add-on's own config files in
   `.ddev/module-developer/config/` (or, for `phpcs`, download the canonical
   `phpcs.xml.dist` from the GitLab Templates repository at runtime so it stays
   current).

Inside the container, bundled config files are mounted at
`/mnt/ddev_config/module-developer/config/`. **Do not use the old path
`/mnt/ddev_config/module-developer/config/`** — the correct path is
`${DDEV_APPROOT}/.ddev/module-developer/config/` or the equivalent absolute path
resolved at runtime.


## PHPStan specifics

The Drupal GitLab CI Docker image pre-installs `mglaman/phpstan-drupal`, so the
template's `phpstan.neon` does not reference it explicitly. Locally there is no
pre-built image, so the `phpstan` command must inject the extension when no
project-level config is found.

A complication: `mglaman/phpstan-drupal`'s autoloader calls
`InstalledVersions::getInstallPath('drupal/core')`. When PHPStan runs as a globally
installed phar its bundled `Composer\InstalledVersions` only knows about global
packages, so the lookup throws `OutOfBoundsException`. The fix is to load the
project's `vendor/autoload.php` as a `bootstrapFiles` entry **before** the mglaman
extension loads. The `phpstan` command builds two temporary neon files at runtime to
guarantee that ordering:

```
BOOTSTRAP_NEON  → parameters.bootstrapFiles: [project vendor/autoload.php]
TMPCONFIG       → includes: [BOOTSTRAP_NEON, extension.neon, rules.neon] + parameters
```

Both temp files are deleted after PHPStan exits.


## phpcompat specifics

`phpcompatibility/php-compatibility` only supports phpcs ^3.x, not ^4.x. The
global Composer install uses phpcs ^4 (matching Drupal 11 CI). To avoid a version
conflict, `phpcompat` installs its own isolated phpcs 3.x + PHPCompatibility suite
under `/usr/local/phpcompat/` and always invokes that binary directly — never the
project-local or global phpcs 4.x binary.


## Bundled default configs

| File | Tool | Notes |
| ---- | ---- | ----- |
| `module-developer/config/phpcs.xml` | phpcs / phpcbf | Enforces `Drupal` standard; `DrupalPractice` is commented out |
| `module-developer/config/phpstan.neon` | phpstan | Level 2, Drupal file extensions |
| `module-developer/config/phpmd-ruleset.xml` | phpmd | Drupal-appropriate ruleset |
| `module-developer/config/.stylelintrc.json` | stylelint | Matches GitLab Templates |
| `module-developer/config/.eslintrc.json` | eslint | Matches GitLab Templates |

Default configs should match the [Drupal GitLab Templates](https://git.drupalcode.org/project/gitlab_templates)
defaults exactly. When the upstream template changes a default, update the
corresponding file here.


## Key invariants for contributors

- **Parity with CI is the north star.** Any behaviour difference between a local
  `ddev phpcs` run and the CI `phpcs` job is a bug.
- **No per-start installation.** All tools must be installed in `web-build/Dockerfile`.
  Commands must not `composer require` or `npm install` at runtime.
- **Project-local binary wins.** When the project vendors a tool (e.g. phpcs via
  `drupal/coder`), that binary takes precedence over the globally installed one.
- **`HostWorkingDir: true` is set on every command** so the container's working
  directory matches wherever the developer ran the `ddev` command on the host.
- **Host-path arguments are normalized before exec.** Every command sources
  `module-developer/lib/host-paths.sh` and calls `ddev_normalize_host_paths "$@"`
  immediately after binary resolution, so absolute host paths passed as arguments
  resolve inside the container. New commands must follow the same pattern.
- **Temp files must always be cleaned up.** Commands that create temp neon/config
  files must remove them in all exit paths (capture exit code, then `rm -f`, then
  `exit`).
- **Config file paths inside the container** — bundled configs are available at
  `/mnt/ddev_config/module-developer/config/<file>` (the DDEV mount point for files
  in `.ddev/`). Use this path in command scripts, not the host-side
  `.ddev/module-developer/config/` path.


## Adding a new command

1. Add a `commands/web/<toolname>` bash script following the binary-resolution /
   default-path / config-priority pattern above.
2. Add the command to `install.yaml` under `project_files`.
3. Add tool installation to `web-build/Dockerfile` (Composer global require or
   `npm install -g`).
4. If the tool has a configurable default, add a bundled config to
   `module-developer/config/` and list it in `install.yaml`.
5. Add a Bats test in `tests/test.bats` that verifies the command exits 0 on a
   clean fixture and produces expected output.
6. Document the new command in `README.md`.


## Testing

Tests use [Bats](https://bats-core.readthedocs.io/en/stable/). Run them after
initialising the submodules:

```bash
git submodule update --init
./tests/bats/bin/bats ./tests
```

Tests run automatically on every push via GitHub Actions and on a nightly schedule.
