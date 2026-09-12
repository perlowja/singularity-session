#!/usr/bin/env bash
set -eu

if [ "${1:-}" = "-S" ]; then
    printf '%s\n' "${SINGULARITY_SAFE_MODE:-0}" >> "$SINGULARITY_TEST_ATTEMPTS"
    if [ "${SINGULARITY_SAFE_MODE:-0}" = "1" ]; then
        exit 0
    fi
    exit "${SINGULARITY_TEST_NORMAL_EXIT:-134}"
fi

if [ "${SINGULARITY_TEST_FAKE_DESKTOP:-0}" = "1" ]; then
    printf 'shell\n' >> "$SINGULARITY_TEST_SHELL_ATTEMPTS"
    exit 1
fi

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/singularity-session-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/state" "$TEST_DIR/runtime"
chmod 700 "$TEST_DIR/runtime"

export XDG_STATE_HOME="$TEST_DIR/state"
export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
export DBUS_SESSION_BUS_ADDRESS="test-bus"
export GDM_SESSION_DBUS_ADDRESS=""
export SINGULARITY_LABWC_BINARY="$0"
export SINGULARITY_DESKTOP_SESSION_BINARY="$0"
export SINGULARITY_SESSION_BUILD_ID="safe-mode-test-build"
export SINGULARITY_TEST_ATTEMPTS="$TEST_DIR/attempts"

LAUNCHER="$(dirname "$0")/../src/singularity-labwc-session"
bash "$LAUNCHER"

EXPECTED=$(printf '0\n0\n1')
ACTUAL=$(cat "$SINGULARITY_TEST_ATTEMPTS")
[ "$ACTUAL" = "$EXPECTED" ] || {
    echo "unexpected first-launch attempts: $ACTUAL" >&2
    exit 1
}

MARKER="$XDG_STATE_HOME/singularity/safe-mode"
[ -f "$MARKER" ]
[ "$(stat -c %a "$MARKER")" = "600" ]
grep -Fx "build_id=safe-mode-test-build" "$MARKER" >/dev/null
grep -Fx "reason=repeated-session-failure" "$MARKER" >/dev/null

: > "$SINGULARITY_TEST_ATTEMPTS"
bash "$LAUNCHER"
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "1" ] || {
    echo "matching marker did not start Safe Mode directly" >&2
    exit 1
}

: > "$SINGULARITY_TEST_ATTEMPTS"
export SINGULARITY_SESSION_BUILD_ID="safe-mode-test-new-build"
bash "$LAUNCHER"
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "$EXPECTED" ] || {
    echo "changed build did not retry normal mode" >&2
    exit 1
}
grep -Fx "build_id=safe-mode-test-new-build" "$MARKER" >/dev/null

: > "$SINGULARITY_TEST_ATTEMPTS"
export SINGULARITY_FORCE_NORMAL=1
bash "$LAUNCHER"
unset SINGULARITY_FORCE_NORMAL
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "$EXPECTED" ] || {
    echo "force-normal did not bypass the matching marker" >&2
    exit 1
}

rm -f "$MARKER"
: > "$SINGULARITY_TEST_ATTEMPTS"
SINGULARITY_SAFE_MODE=1 bash "$LAUNCHER"
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "1" ] || {
    echo "explicit Safe Mode did not start directly" >&2
    exit 1
}
[ ! -e "$MARKER" ] || {
    echo "explicit Safe Mode unexpectedly created a persistent marker" >&2
    exit 1
}

: > "$SINGULARITY_TEST_ATTEMPTS"
export SINGULARITY_TEST_NORMAL_EXIT=0
bash "$LAUNCHER"
unset SINGULARITY_TEST_NORMAL_EXIT
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "0" ] || {
    echo "clean early exit unexpectedly retried" >&2
    exit 1
}
[ ! -e "$MARKER" ] || {
    echo "clean early exit unexpectedly entered Safe Mode" >&2
    exit 1
}

# The inner shell supervisor must escalate repeated failures even when each
# shell instance lives longer than the old three-second cutoff.
INNER_STATE="$TEST_DIR/inner-state"
mkdir -p "$INNER_STATE"
export XDG_STATE_HOME="$INNER_STATE"
export SINGULARITY_DESKTOP_BINARY="$0"
export SINGULARITY_TEST_FAKE_DESKTOP=1
export SINGULARITY_TEST_SHELL_ATTEMPTS="$TEST_DIR/shell-attempts"
export SINGULARITY_SESSION_SUPERVISOR_ONLY=1
DESKTOP_LAUNCHER="$(dirname "$0")/../src/singularity-desktop-session"
set +e
bash -c 'trap "" TERM; bash "$1" & child=$!; wait "$child"' _ "$DESKTOP_LAUNCHER"
set -e
[ "$(wc -l < "$SINGULARITY_TEST_SHELL_ATTEMPTS")" -eq 3 ] || {
    echo "inner supervisor did not stop after its crash budget" >&2
    exit 1
}
[ -f "$INNER_STATE/singularity/safe-mode-request" ] || {
    echo "inner supervisor did not request Safe Mode" >&2
    exit 1
}
[ "$(stat -c %a "$INNER_STATE/singularity/safe-mode-request")" = "600" ]
grep -Fx "build_id=safe-mode-test-new-build" \
    "$INNER_STATE/singularity/safe-mode-request" >/dev/null

unset SINGULARITY_SESSION_SUPERVISOR_ONLY SINGULARITY_TEST_FAKE_DESKTOP
export SINGULARITY_TEST_ATTEMPTS="$TEST_DIR/request-attempts"
: > "$SINGULARITY_TEST_ATTEMPTS"
bash "$LAUNCHER"
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "1" ] || {
    echo "matching shell-crash request did not start Safe Mode directly" >&2
    exit 1
}

# An update between the shell crash and the next launcher invocation must make
# the one-shot request stale, just like a persistent Safe Mode marker.
rm -f "$INNER_STATE/singularity/safe-mode"
printf 'version=1\nbuild_id=safe-mode-test-new-build\nreason=repeated-shell-failure\n' \
    > "$INNER_STATE/singularity/safe-mode-request"
chmod 600 "$INNER_STATE/singularity/safe-mode-request"
: > "$SINGULARITY_TEST_ATTEMPTS"
export SINGULARITY_SESSION_BUILD_ID="safe-mode-test-post-update"
bash "$LAUNCHER"
[ "$(cat "$SINGULARITY_TEST_ATTEMPTS")" = "$EXPECTED" ] || {
    echo "stale shell-crash request survived a build change" >&2
    exit 1
}
grep -Fx "build_id=safe-mode-test-post-update" \
    "$INNER_STATE/singularity/safe-mode" >/dev/null
