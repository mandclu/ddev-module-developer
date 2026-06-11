#!/usr/bin/env bash
#ddev-generated

# Shared helper sourced by every command in commands/web/.
#
# DDEV commands run with `## HostWorkingDir: true`, which maps the host's current
# working directory into the container so a bare `ddev phpcs` targets whatever
# module the developer cd'd into. Arguments, however, are passed through verbatim:
# an absolute *host* path (e.g. /Users/me/Sites/project/web/modules/custom/foo)
# arrives inside the container unchanged and does not resolve, because the project
# is mounted at ${DDEV_APPROOT} (/var/www/html).
#
# ddev_normalize_host_paths rewrites such arguments to their in-container
# equivalent so callers — IDE external tools, file watchers, AI agents — can pass
# absolute host paths. It is host-root agnostic: rather than assuming a docroot or
# a known host prefix, it strips leading path components until the remainder
# resolves under ${DDEV_APPROOT}. This covers paths anywhere in the project
# (web/modules/..., top-level recipes/..., etc.).
#
# The rewrite is a no-op for:
#   - relative arguments (web/modules/custom/foo),
#   - flags (--standard=Drupal),
#   - absolute paths that already exist in the container,
#   - absolute paths whose tail does not resolve under ${DDEV_APPROOT}.
#
# Known limitation: arguments containing glob wildcards (/abs/path/**/*.css) are
# left untouched because the existence test cannot match a glob; pass those
# relative to the project root instead.
#
# The rewritten argument list is returned in the DDEV_NORMALIZED_ARGS array.
# Usage:
#   source /mnt/ddev_config/module-developer/lib/host-paths.sh
#   ddev_normalize_host_paths "$@"
#   set -- "${DDEV_NORMALIZED_ARGS[@]}"
ddev_normalize_host_paths() {
  DDEV_NORMALIZED_ARGS=()
  local arg rel
  for arg in "$@"; do
    if [ "${arg#/}" != "${arg}" ] && [ ! -e "${arg}" ]; then
      rel="${arg}"
      while [ "${rel#*/}" != "${rel}" ]; do
        rel="${rel#*/}"
        if [ -e "${DDEV_APPROOT}/${rel}" ]; then
          arg="${DDEV_APPROOT}/${rel}"
          break
        fi
      done
    fi
    DDEV_NORMALIZED_ARGS+=("${arg}")
  done
}
