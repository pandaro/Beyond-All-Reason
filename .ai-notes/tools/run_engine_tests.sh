#!/usr/bin/env bash
# Runs luaui/Tests/shard/*.lua, or the given files, inside the engine in a headless game, synced and unsynced.
# The PASS of the BAR test runner does not count: see T4 in .ai-notes/handoff.md.
#
# Usage: .ai-notes/tools/run_engine_tests.sh [luaui/Tests/shard/test_x.lua ...]
# Environment:
#   ENGINE_DIR  engine folder (default: the newest under ~/.spring/engine)
#   WRITE_DIR   Spring write dir (default: a separate one under ${TMPDIR:-/tmp}, linked to the games, maps and
#               packages of ~/.spring, so that ~/.spring/infolog.txt of an open game is left alone;
#               WRITE_DIR=~/.spring runs it as CLAUDE.local.md describes)
# Exit status: 0 when both sides ran, nothing failed and the negative control was detected.
set -u

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SPRING_HOME="${SPRING_HOME:-$HOME/.spring}"
ENGINE_DIR="${ENGINE_DIR:-$(ls -d "$SPRING_HOME"/engine/*/ | sort | tail -n 1)}"
GADGET_SOURCE="$REPO/.ai-notes/tools/engine_tests_gadget.lua"
GADGET="$REPO/luarules/gadgets/dbg_shard_engine_tests.lua"
TAG="[SHARD-ENGINE-TESTS]"

if [ -z "${WRITE_DIR:-}" ]; then
	WRITE_DIR="${TMPDIR:-/tmp}/shard-engine-tests"
	mkdir -p "$WRITE_DIR"
	for link in games maps packages pool rapid; do
		if [ -e "$SPRING_HOME/$link" ] && [ ! -e "$WRITE_DIR/$link" ]; then
			ln -s "$SPRING_HOME/$link" "$WRITE_DIR/$link"
		fi
	done
	if [ ! -e "$WRITE_DIR/springsettings.cfg" ]; then
		cp "$REPO/tools/headless_testing/springsettings.cfg" "$WRITE_DIR/springsettings.cfg"
	fi
fi

if [ -e "$GADGET" ]; then
	echo "$GADGET already exists: remove it first" >&2
	exit 2
fi

cleanup() {
	rm -f "$GADGET"
}
trap cleanup EXIT INT TERM

if [ "$#" -gt 0 ]; then
	list="{"
	for file in "$@"; do
		list="$list \"$file\","
	done
	list="$list }"
	sed "s|^local REQUESTED_FILES = nil -- @REQUESTED_FILES@|local REQUESTED_FILES = $list|" "$GADGET_SOURCE" > "$GADGET"
else
	cp "$GADGET_SOURCE" "$GADGET"
fi

"$ENGINE_DIR/spring-headless" --isolation --write-dir "$WRITE_DIR" "$REPO/tools/headless_testing/startscript.txt" \
	> "$WRITE_DIR/engine_tests_console.txt" 2>&1
status=$?
cleanup

echo "engine exit status: $status; infolog: $WRITE_DIR/infolog.txt"
grep -F "$TAG" "$WRITE_DIR/infolog.txt" | sed -E 's/^\[t=[^]]*\]\[f=[^]]*\] //'

summaries=$(grep -F "$TAG" "$WRITE_DIR/infolog.txt" | grep -c "SUMMARY")
bad=$(grep -F "$TAG" "$WRITE_DIR/infolog.txt" | grep "SUMMARY" | grep -c -v " 0 failed, .*negative control detected")
if [ "$summaries" -ne 2 ] || [ "$bad" -ne 0 ]; then
	echo "RESULT: FAILED ($summaries of 2 summaries, $bad with failures or without the negative control)"
	exit 1
fi
echo "RESULT: ok"
