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
  lib/              # init.sh — sourced by every command before it reads "$@"
web-build/
  Dockerfile        # Installs all tools at container-build time
install.yaml        # DDEV add-on manifest
tests/test.bats     # Bats integration tests
```


## Commands

Each file in `commands/web/` is a bash script that DDEV injects as a `ddev <name>`
command running inside the web container.

| Command        | Tool                                     | Language  |
| -------------- | ---------------------------------------- | --------- |
| `checks`       | Orchestrator — runs all CI checks        | all       |
| `parallel-lint`| php-parallel-lint (PHP syntax)           | PHP       |
| `phpcs`        | PHP_CodeSniffer                          | PHP       |
| `phpcbf`       | PHP Code Beautifier and Fixer            | PHP       |
| `phpstan`      | PHPStan + mglaman/phpstan-drupal         | PHP       |
| `phpmd`        | PHP Mess Detector                        | PHP       |
| `rector`       | Drupal Rector                            | PHP       |
| `phpcompat`    | PHP compatibility checker                | PHP       |
| `stylelint`    | Stylelint                                | CSS/SCSS  |
| `eslint`       | ESLint + Prettier + yml plugin           | JS/YAML   |
| `cspell`       | CSpell                                   | all       |

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

### 1b. Source `init.sh` before reading arguments

Every command sources the shared init file as its first step — after resolving the
binary but before it reads `"$@"`, applies defaults, parses arguments, or builds
derived config/tool arguments:

```bash
# shellcheck source=../../module-developer/lib/init.sh
source /mnt/ddev_config/module-developer/lib/init.sh
```

That single line is the entire hook; there is no per-command boilerplate.
`module-developer/lib/init.sh` is sourced with no arguments, so inside it `"$@"`
is the *caller's* positional parameters, and a top-level `set --` in `init.sh`
rewrites the calling command's `"$@"` in place.

`init.sh` currently normalizes absolute host-path arguments:
`HostWorkingDir: true` only maps the *current directory* into the container;
arguments are passed through verbatim, so an absolute *host* path argument does not
resolve inside the container. `init.sh` converts it to its in-container equivalent
by stripping leading components until the remainder resolves under `${DDEV_APPROOT}`.
This lets IDE external tools and agents pass full host paths. It is a no-op for
relative paths, flags, already-in-container paths, and unresolvable paths. `init.sh`
must be sourced **before** the no-path default so the default and config-resolution
logic see container paths. `init.sh` is also the designated home for any future
shared global utilities the commands need.

**Known limitation — glob wildcards:** arguments containing `*` or `?` are left
untouched. Pass glob patterns as relative paths (e.g. `"**/*.css"`) rather than
absolute host paths.

**Known limitation — ambiguous path suffix:** the algorithm strips one leading
component at a time and stops at the first suffix that resolves under
`${DDEV_APPROOT}`. If the project contains a directory whose name matches a trailing
component of the host path (e.g. a `web/` docroot and a host path of
`/anything/web`), the shorter match wins. In practice this is rare because IDE tools
pass full module paths, not short generic names.

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

Inside the container, bundled config files are available at both
`/mnt/ddev_config/module-developer/config/<file>` (DDEV's mount point) and
`${DDEV_APPROOT}/.ddev/module-developer/config/<file>` (the host-side path as seen
from inside the container). Both resolve to the same files. Prefer the
`${DDEV_APPROOT}/.ddev/` form in new command scripts for consistency with how other
paths in the scripts are expressed.


## `checks` command

`checks` is an orchestrator, not a wrapper around a single binary. It calls the other
command scripts directly via `bash "${COMMANDS_DIR}/<script>"` — those scripts run in
the same container context with the same environment variables and working directory.
Using `bash script` (rather than invoking `ddev <command>` again) avoids spawning a
new DDEV process per check, and the individual scripts' `exec` calls propagate exit
codes correctly through the subshell.

### Three phases

**Phase 1 — CI checks** (always, in Drupal GitLab Templates job order):
`parallel-lint` → `phpcs` → `phpstan` → `eslint` → `stylelint` → `cspell`

**Phase 2 — Bonus checks** (`--bonus` flag only; not part of Drupal CI):
`phpmd` → `phpcompat`

**Phase 3 — PHPUnit** (only when Phase 1 + 2 produced zero hard failures, and only
when the Drupal test bootstrap is installed). The bootstrap check mirrors the phpunit
command itself: `web/core/tests/bootstrap.php` must exist and `vendor/behat/mink`
must be present.

### GitLab CI variable integration

`checks` reads variables from `${DDEV_APPROOT}/.gitlab-ci.yml` (the project root) —
not from the host working directory — because the project root is the only reliable
location for the project's CI config regardless of where the developer ran the command.

**SKIP variables** — a job with its `SKIP_*` variable set to `"1"` is skipped entirely
and shown as `-` in the summary. Does not affect the exit status.

| Variable              | Skips            |
| --------------------- | ---------------- |
| `SKIP_COMPOSER_LINT`  | `parallel-lint`  |
| `SKIP_PHPCS`          | `phpcs`          |
| `SKIP_PHPSTAN`        | `phpstan`        |
| `SKIP_ESLINT`         | `eslint`         |
| `SKIP_STYLELINT`      | `stylelint`      |
| `SKIP_CSPELL`         | `cspell`         |
| `SKIP_PHPUNIT`        | `phpunit`        |

**`_ALLOW_FAILURE` variables** — a job whose allow_failure flag is truthy shows
failures as `⚠` (warnings) instead of `✗` (hard failures). If every failure in the
run was a warning, `checks` exits 0 with `Result: passed with warnings`. If any hard
failure occurred, it exits 1 with `Result: FAILED`.

Per-tool variables (`_PHPCS_ALLOW_FAILURE`, `_PHPSTAN_ALLOW_FAILURE`, etc.) take
precedence over the global `_ALL_VALIDATE_ALLOW_FAILURE`, matching the precedence
rules of the GitLab CI pipeline. Bonus checks always use allow_failure = 0; they have
no GitLab CI job counterpart and therefore no CI variable.

### Exit codes
- `0` — all checks passed (or all failures were warnings)
- `1` — one or more hard failures occurred


## `parallel-lint` specifics

`parallel-lint` wraps `php-parallel-lint/php-parallel-lint`. It is the fastest check
in the suite because it only validates PHP syntax (parse errors) and nothing else.
In the Drupal GitLab CI pipeline it runs inside the `composer-lint` job as the first
quality gate, providing immediate feedback on broken PHP before heavier tools run.

The command passes `--extensions php,module,install,theme,inc,profile` to match the
file types Drupal CI checks, and `--exclude vendor --exclude node_modules` to avoid
scanning third-party code. The `_PARALLEL_LINT_EXTRA` variable from `.gitlab-ci.yml`
is injected as extra flags, matching the pattern of other commands.

The binary is symlinked as `/usr/local/bin/parallel-lint` (not `php-parallel-lint`,
which is the legacy alias). The skip variable used by `checks` is `SKIP_COMPOSER_LINT`
(not `SKIP_PARALLEL_LINT`) because in CI the tool lives inside the `composer-lint` job.


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
- **Every command sources `init.sh` before reading positional arguments.** A single
  `source /mnt/ddev_config/module-developer/lib/init.sh` line, placed after binary
  resolution but before the command reads `"$@"`, applies defaults, or parses
  arguments, normalizes absolute host-path arguments (and is the hook for any future
  shared utilities). New commands must follow the same pattern.
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
2. Source `module-developer/lib/init.sh` after binary resolution and **before** the
   script reads `"$@"`, applies defaults, or parses arguments, so the command gets
   host-path normalization (see "Source `init.sh` before reading arguments" above):
   ```bash
   # shellcheck source=../../module-developer/lib/init.sh
   source /mnt/ddev_config/module-developer/lib/init.sh
   ```
   Skipping this means absolute host paths silently won't resolve for the command.
3. Add the command to `install.yaml` under `project_files`.
4. Add tool installation to `web-build/Dockerfile` (Composer global require or
   `npm install -g`).
5. If the tool has a configurable default, add a bundled config to
   `module-developer/config/` and list it in `install.yaml`.
6. Add a Bats test in `tests/fixtures.bats` that verifies the command exits 0 on a
   clean fixture and non-zero on a dirty fixture.
7. If the new tool has a corresponding Drupal GitLab CI job, add it to the Phase 1
   sequence in `commands/web/checks` with the appropriate `SKIP_*` and
   `_*_ALLOW_FAILURE` variable names. Also add `parallel-lint` to the binary loop in
   `tests/helpers.bash` and list the new command in the `ddev help` assertion.
8. Document the new command in `README.md` and update the command table in `AGENTS.md`.


## Testing

Tests use [Bats](https://bats-core.readthedocs.io/en/stable/). Run them after
initialising the submodules:

```bash
git submodule update --init
./tests/bats/bin/bats ./tests
```

Tests run automatically on every push via GitHub Actions and on a nightly schedule.
