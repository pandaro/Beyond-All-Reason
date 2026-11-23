#!/usr/bin/env bash
# Runs a headless game with AI teams for a number of game minutes and prints the lines that matter:
# the control gadget's report per minute ([SHARD-GAME]), the loader's lines ([AI Loader], Shard relay) and errors.
#
# Usage: .ai-notes/tools/run_engine_game.sh <startscript> <minutes>
#   The startscript (see .ai-notes/tools/startscripts/) has @QUIT_FRAME@ where the game must end, in debugcommands.
# Environment: ENGINE_DIR, WRITE_DIR as in run_engine_tests.sh (default write dir: ${TMPDIR:-/tmp}/shard-engine-game).
set -u

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <startscript> <minutes>" >&2
	exit 2
fi
STARTSCRIPT="$1"
MINUTES="$2"

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SPRING_HOME="${SPRING_HOME:-$HOME/.spring}"
ENGINE_DIR="${ENGINE_DIR:-$(ls -d "$SPRING_HOME"/engine/*/ | sort | tail -n 1)}"
GADGET_SOURCE="$REPO/.ai-notes/tools/engine_game_gadget.lua"
GADGET="$REPO/luarules/gadgets/dbg_shard_engine_game.lua"
END_FRAME=$((MINUTES * 1800))
QUIT_FRAME=$((END_FRAME + 30))

if [ -z "${WRITE_DIR:-}" ]; then
	WRITE_DIR="${TMPDIR:-/tmp}/shard-engine-game"
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

engine_pid=""
cleanup() {
	if [ -n "$engine_pid" ] && kill -0 "$engine_pid" 2>/dev/null; then
		kill "$engine_pid"
	fi
	rm -f "$GADGET"
}
trap cleanup EXIT INT TERM

sed "s|^local END_FRAME = .*|local END_FRAME = $END_FRAME|" "$GADGET_SOURCE" > "$GADGET"
sed "s|@QUIT_FRAME@|$QUIT_FRAME|" "$STARTSCRIPT" > "$WRITE_DIR/game_startscript.txt"

started=$(date +%s)
stdbuf -oL -eL "$ENGINE_DIR/spring-headless" --isolation --write-dir "$WRITE_DIR" "$WRITE_DIR/game_startscript.txt" \
	> "$WRITE_DIR/engine_game_console.txt" 2>&1 &
engine_pid=$!
wait "$engine_pid"
status=$?
cleanup

echo "engine exit status: $status after $(($(date +%s) - started)) s; infolog: $WRITE_DIR/infolog.txt"
grep -E "\[SHARD-GAME\]|\[AI Loader\]|Shard relay|Shard AI (un)?sync gadget|Shard memory record|[Ee]rror" "$WRITE_DIR/infolog.txt" \
	| grep -v "setfenv: cannot change this environment" \
	| sed -E 's/^\[t=[^]]*\]\[f=[^]]*\] //'
