#!/usr/bin/env bash
# Smoke tests for ntree against throwaway repos. Run: test/smoke.sh
set -euo pipefail

NTREE="${NTREE:-$(cd "$(dirname "$0")/.." && pwd)/bin/ntree}"   # override to test another build
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/config"   # keep the .ntreerc allow-list out of the real one
export XDG_STATE_HOME="$TMP/state"     # and the machine-wide port registry

pass=0 fail=0
check() {  # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); printf 'ok    %s\n' "$desc"
  else fail=$((fail + 1)); printf 'FAIL  %s\n' "$desc"; fi
}
fails() { ! "$@"; }

new_repo() {  # new_repo <dir>
  git init -q "$1"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

# --- read-only commands don't create .ntree/ ---------------------------------
new_repo "$TMP/ro"
( cd "$TMP/ro" && "$NTREE" list && "$NTREE" path nope; "$NTREE" __complete workspaces ) >/dev/null 2>&1 || true
check "list/path/__complete leave a fresh repo untouched" test ! -e "$TMP/ro/.ntree"

# --- new: ignores, including an exclude file with no trailing newline --------
R="$TMP/repo"; new_repo "$R"
printf 'last-pattern' >> "$R/.git/info/exclude"       # unterminated last line
( cd "$R" && "$NTREE" new feat/a ) >/dev/null 2>&1 || true
check "workspace created" test -d "$R/.ntree/feat-a"
check "existing last pattern not glued" grep -qx 'last-pattern' "$R/.git/info/exclude"
check ".env.workspace excluded on its own line" grep -qx '.env.workspace' "$R/.git/info/exclude"
check "main checkout status is clean (.ntree/ ignored)" test -z "$(git -C "$R" status --porcelain)"
check "worktree status is clean (.env.workspace ignored)" test -z "$(git -C "$R/.ntree/feat-a" status --porcelain)"

# --- workspace name collisions ('/' maps to '-') ------------------------------
check "new refuses a branch that maps to a taken name" fails bash -c "cd '$R' && '$NTREE' new feat-a"
check "run refuses a branch that maps to a taken name" fails bash -c "cd '$R' && '$NTREE' run feat-a -- true"
check "run reuses the matching branch" bash -c "cd '$R' && '$NTREE' run feat/a -- true"

# --- completion + shell integration -------------------------------------------
check "__complete lists workspaces from inside a worktree" \
  bash -c "cd '$R/.ntree/feat-a' && '$NTREE' __complete workspaces | grep -qx feat-a"
check "__complete lists commands" bash -c "'$NTREE' __complete commands | grep -qx doctor"
check "shell-init cds into a workspace" bash -c "
  ntree_bin='$NTREE'; eval \"\$(\"\$ntree_bin\" shell-init | sed \"s|command ntree|\$ntree_bin|g\")\"
  cd '$R' && ntree feat-a && [ \"\$(pwd -P)\" = \"\$(cd '$R/.ntree/feat-a' && pwd -P)\" ]"

# --- rm ------------------------------------------------------------------------
( cd "$R" && "$NTREE" rm feat-a --force ) >/dev/null 2>&1 || true
check "rm removes the worktree" test ! -e "$R/.ntree/feat-a"

# --- linked paths ----------------------------------------------------------------
L="$TMP/linked"; new_repo "$L"
echo t > "$L/tracked.md"; git -C "$L" add tracked.md
git -C "$L" -c user.name=t -c user.email=t@t commit -q -m tracked
echo '.ntreerc' >> "$L/.git/info/exclude"
mkdir -p "$L/ctx" "$L/.claude"; echo spec > "$L/ctx/a.md"; echo '{}' > "$L/.claude/settings.local.json"
set_links() {  # set_links <NTREE_LINK_PATHS> [extra .ntreerc line]
  printf "NTREE_LINK_PATHS='%s'\n%s\n" "$1" "${2:-}" > "$L/.ntreerc"
  ( cd "$L" && "$NTREE" allow ) >/dev/null 2>&1 || true
}
set_links 'ctx .claude/settings.local.json'
( cd "$L" && "$NTREE" new w1 ) >/dev/null 2>&1 || true
W="$L/.ntree/w1"
check "dir is linked with a relative target" test "$(readlink "$W/ctx")" = "../../ctx"
check "nested file is linked with a relative target" \
  test "$(readlink "$W/.claude/settings.local.json")" = "../../../.claude/settings.local.json"
echo edit >> "$W/ctx/a.md"
check "edits through a link land in main" grep -qx edit "$L/ctx/a.md"
check "worktree status is clean with links" test -z "$(git -C "$W" status --porcelain)"
check "main status is clean with linked sources" test -z "$(git -C "$L" status --porcelain)"

mkdir "$L/notes"
set_links 'ctx .claude/settings.local.json notes'
( cd "$L" && "$NTREE" sync w1 ) >/dev/null 2>&1 || true
check "sync links a path added after creation" test -L "$W/notes"

mv "$L/ctx" "$L/ctx.bak"
check "doctor flags a broken link" bash -c "cd '$L' && '$NTREE' doctor 2>&1 | grep -q 'ctx: broken link'"
mv "$L/ctx.bak" "$L/ctx"

set_links 'tracked.md'
check "tracked path is refused" fails bash -c "cd '$L' && '$NTREE' new w2"
check "refused new leaves no worktree" test ! -e "$L/.ntree/w2"
set_links 'ctx' "NTREE_CLONE_DIRS='ctx'"
check "path in both link and clone lists is refused" fails bash -c "cd '$L' && '$NTREE' new w3"
set_links '../outside'
check "path escaping the repo is refused" fails bash -c "cd '$L' && '$NTREE' new w4"

set_links 'ctx'
( cd "$L" && "$NTREE" rm w1 --force ) >/dev/null 2>&1 || true
check "rm keeps the link source" test -f "$L/ctx/a.md"

# --- clone dirs -------------------------------------------------------------------
C="$TMP/clone"; new_repo "$C"
mkdir -p "$C/deps" "$C/tdir"; echo v1 > "$C/deps/x"; echo t > "$C/tdir/f"
git -C "$C" add tdir && git -C "$C" -c user.name=t -c user.email=t@t commit -q -m tdir
echo '.ntreerc' >> "$C/.git/info/exclude"
printf "NTREE_CLONE_DIRS='deps tdir'\n" > "$C/.ntreerc"; ( cd "$C" && "$NTREE" allow ) >/dev/null 2>&1
( cd "$C" && "$NTREE" new c1 ) >/dev/null 2>&1 || true
check "clone dir copied into a new workspace" grep -qx v1 "$C/.ntree/c1/deps/x"
echo v2 > "$C/deps/x"; echo local > "$C/.ntree/c1/tdir/f"
( cd "$C" && "$NTREE" sync-deps c1 ) >/dev/null 2>&1 || true
check "sync-deps refreshes a clone dir" grep -qx v2 "$C/.ntree/c1/deps/x"
check "sync-deps never replaces a dir the branch tracks" grep -qx local "$C/.ntree/c1/tdir/f"

# --- rm guards uncommitted work ---------------------------------------------------
D="$TMP/dirty"; new_repo "$D"
( cd "$D" && "$NTREE" new d1 ) >/dev/null 2>&1 || true
echo wip > "$D/.ntree/d1/wip.txt"
check "rm refuses a workspace with uncommitted changes" fails bash -c "cd '$D' && echo y | '$NTREE' rm d1"
check "refused rm keeps the work" test -f "$D/.ntree/d1/wip.txt"
check "rm --force discards it" bash -c "cd '$D' && '$NTREE' rm d1 --force && test ! -e '$D/.ntree/d1'"

# --- no half-made workspace when ports run out --------------------------------------
P="$TMP/ports"; new_repo "$P"
echo '.ntreerc' >> "$P/.git/info/exclude"
printf 'NTREE_PORT_RANGE_START=3901\nNTREE_PORT_RANGE_END=3901\n' > "$P/.ntreerc"; ( cd "$P" && "$NTREE" allow ) >/dev/null 2>&1
( cd "$P" && "$NTREE" new p1 ) >/dev/null 2>&1 || true
check "new fails when no port is free" fails bash -c "cd '$P' && '$NTREE' new p2"
check "failed new creates no worktree" test ! -e "$P/.ntree/p2"
check "failed new creates no branch" fails git -C "$P" show-ref --verify --quiet refs/heads/p2

# --- ports are unique across repos ---------------------------------------------------
P2="$TMP/ports2"; new_repo "$P2"
echo '.ntreerc' >> "$P2/.git/info/exclude"; cp "$P/.ntreerc" "$P2/.ntreerc"
check "another repo can't take a port reserved elsewhere" fails bash -c "cd '$P2' && '$NTREE' new q1"
( cd "$P" && "$NTREE" rm p1 --force ) >/dev/null 2>&1 || true
check "rm releases the port machine-wide" bash -c "cd '$P2' && '$NTREE' new q1"

# --- run: argument handling + terminal -------------------------------------------
G="$TMP/run"; new_repo "$G"
check "several args run exactly as given" \
  bash -c "cd '$G' && '$NTREE' run r -- printf '[%s]' 'two words' 2>/dev/null | grep -qxF '[two words]'"
check "one arg is a shell string (\$PORT expands)" \
  bash -c "cd '$G' && '$NTREE' run r -- 'echo port=\$PORT' 2>/dev/null | grep -qE '^port=[0-9]+$'"
check "bare run reuses the remembered command" \
  bash -c "cd '$G' && '$NTREE' run r 2>/dev/null | grep -qE '^port=[0-9]+$'"
foreground_has_tty() {  # run under a pseudo-terminal (BSD vs util-linux script)
  local line="cd '$G' && '$NTREE' run r -- 'test -t 1 && echo has-tty'" out
  if [[ "$(uname -s)" == Darwin ]]; then out="$(script -q /dev/null bash -c "$line" </dev/null 2>/dev/null)"
  else out="$(script -qec "$line" /dev/null </dev/null 2>/dev/null)"; fi
  [[ "$out" == *has-tty* ]]
}
check "foreground run keeps the terminal" foreground_has_tty

# --- linked path removed from config -------------------------------------------------
set_links 'ctx notes'
( cd "$L" && "$NTREE" new w5 ) >/dev/null 2>&1 || true
set_links 'ctx'
check "doctor flags a stale link" bash -c "cd '$L' && '$NTREE' doctor 2>&1 | grep -q 'notes: stale link'"
( cd "$L" && "$NTREE" sync w5 ) >/dev/null 2>&1 || true
check "sync removes the stale link" test ! -e "$L/.ntree/w5/notes"
check "sync keeps the source of a removed link" test -d "$L/notes"

# --- open: EDITOR with flags ---------------------------------------------------------
check "open handles an EDITOR with arguments" \
  bash -c "cd '$G' && EDITOR='echo opened' '$NTREE' open r | grep -q '^opened '"

# --- run --rm cleans up only what it created; --from on an existing branch -------
check "run --rm removes the workspace and the branch it created" \
  bash -c "cd '$G' && '$NTREE' run tmp1 --rm -- true && test ! -e .ntree/tmp1 && ! git show-ref --verify --quiet refs/heads/tmp1"
check "run --rm keeps a branch that got new commits" \
  bash -c "cd '$G' && '$NTREE' run tmp2 --rm -- 'git -c user.name=t -c user.email=t@t commit -q --allow-empty -m x' && git show-ref --verify --quiet refs/heads/tmp2"
check "run --rm keeps a workspace that existed before" bash -c "cd '$G' && '$NTREE' run r --rm -- true && test -d .ntree/r"
git -C "$G" branch exists1
check "--from on an existing branch warns" bash -c "cd '$G' && '$NTREE' new exists1 --from HEAD 2>&1 | grep -q 'ignoring --from'"

# --- moving the repo -------------------------------------------------------------
M="$TMP/move"; new_repo "$M"
( cd "$M" && "$NTREE" new mv1 ) >/dev/null 2>&1 || true
mv "$M" "$TMP/moved"
( cd "$TMP/moved" && "$NTREE" doctor ) >/dev/null 2>&1 || true
check "doctor reconnects worktrees after the repo moves" git -C "$TMP/moved/.ntree/mv1" status
check "moved workspace keeps its registry entry under the new path" \
  bash -c "grep -q '/moved/.ntree/mv1\$' '$XDG_STATE_HOME/ntree/ports' && ! grep -q '/move/.ntree/mv1\$' '$XDG_STATE_HOME/ntree/ports'"

# --- background servers: run -d, stop, untracked servers, port reallocation --------
listening() { local _; for _ in $(seq 1 50); do nc -z 127.0.0.1 "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
closed()    { local _; for _ in $(seq 1 50); do nc -z 127.0.0.1 "$1" 2>/dev/null || return 0; sleep 0.1; done; return 1; }
if command -v python3 >/dev/null 2>&1 && command -v lsof >/dev/null 2>&1; then
  B="$TMP/bg"; new_repo "$B"
  serve='exec python3 -m http.server $PORT --bind 127.0.0.1'
  ( cd "$B" && "$NTREE" run s -d -- "$serve" ) >/dev/null 2>&1 || true
  port="$(jq -r '.workspaces.s.ports[0]' "$B/.ntree/state.json")"
  check "run -d serves on the workspace's PORT" listening "$port"
  check "list shows it running" bash -c "cd '$B' && '$NTREE' list 2>&1 | grep '^s ' | grep -q running"
  ( cd "$B" && "$NTREE" stop s ) >/dev/null 2>&1 || true
  check "stop frees the port" closed "$port"

  ( cd "$B/.ntree/s" && exec python3 -m http.server 3950 --bind 127.0.0.1 >/dev/null 2>&1 ) & disown
  listening 3950 || true
  ( cd "$B" && "$NTREE" stop s ) >/dev/null 2>&1 || true
  check "stop kills an untracked server running in the worktree" closed 3950

  ( cd "$TMP" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) & squatter=$!; disown
  listening "$port" || true
  ( cd "$B" && "$NTREE" run s -d ) >/dev/null 2>&1 || true
  newport="$(jq -r '.workspaces.s.ports[0]' "$B/.ntree/state.json")"
  check "run -d moves to a free port if its own was taken" test "$newport" != "$port"
  check "the moved server is listening" listening "$newport"
  ( cd "$B" && "$NTREE" stop s ) >/dev/null 2>&1 || true
  kill "$squatter" 2>/dev/null || true
else
  printf 'skip  background server tests (need python3 and lsof)\n'
fi

# --- a reused pid is never treated as the workspace's server --------------------
U="$TMP/pid"; new_repo "$U"
( cd "$U" && "$NTREE" new u1 ) >/dev/null 2>&1 || true
sleep 300 & victim=$!; disown
jq --argjson p "$victim" '.workspaces.u1.pid = $p' "$U/.ntree/state.json" > "$TMP/s.json" && mv "$TMP/s.json" "$U/.ntree/state.json"
check "list doesn't show a stranger's pid as running" bash -c "cd '$U' && '$NTREE' list | grep '^u1 ' | grep -q stopped"
( cd "$U" && "$NTREE" stop u1 ) >/dev/null 2>&1 || true
check "stop leaves an unrelated process alone" kill -0 "$victim"
kill "$victim" 2>/dev/null || true

# --- list is pipeable; flags without values fail loudly ------------------------
check "list prints its table to stdout" bash -c "cd '$U' && '$NTREE' list 2>/dev/null | grep -q '^u1 '"
check "a flag missing its value is an error" bash -c "cd '$U' && '$NTREE' new x --from 2>&1 | grep -q 'needs a value'"

# --- new starts from the default branch, not whatever main has checked out ------
V="$TMP/base"; new_repo "$V"
default="$(git -C "$V" branch --show-current)"
git -C "$V" switch -q -c feature && git -C "$V" -c user.name=t -c user.email=t@t commit -q --allow-empty -m feature-only
( cd "$V" && "$NTREE" new nb ) >/dev/null 2>&1 || true
check "new branches from the default branch" \
  test "$(git -C "$V/.ntree/nb" rev-parse HEAD)" = "$(git -C "$V" rev-parse "$default")"
( cd "$V" && "$NTREE" new nb2 --from feature ) >/dev/null 2>&1 || true
check "--from still overrides it" test "$(git -C "$V/.ntree/nb2" log -1 --format=%s)" = feature-only

# --- any branch name git allows works --------------------------------------------
( cd "$V" && "$NTREE" new 'q"x' ) >/dev/null 2>&1 || true
check 'a branch name with a " works' bash -c "cd '$V' && '$NTREE' path 'q\"x' >/dev/null && '$NTREE' list | grep -q '^q\"x '"

# --- parallel new isn't blocked by a slow one; a failed build rolls back --------
W="$TMP/par"; new_repo "$W"; mkdir -p "$W/deps" "$TMP/slowbin" "$TMP/failbin"; echo x > "$W/deps/f"
echo '.ntreerc' >> "$W/.git/info/exclude"
printf "NTREE_CLONE_DIRS='deps'\n" > "$W/.ntreerc"; ( cd "$W" && "$NTREE" allow ) >/dev/null 2>&1
realcp="$(command -v cp)"
printf '#!/bin/sh\nsleep 15; exec %s "$@"\n' "$realcp" > "$TMP/slowbin/cp"; chmod +x "$TMP/slowbin/cp"
( cd "$W" && PATH="$TMP/slowbin:$PATH" "$NTREE" new slow ) >/dev/null 2>&1 & slowpid=$!
sleep 2
started=$(date +%s)
( cd "$W" && "$NTREE" new quick ) >/dev/null 2>&1 || true
check "a second new doesn't wait for a slow one" test $(( $(date +%s) - started )) -lt 8
check "the second new succeeded" test -d "$W/.ntree/quick"
wait "$slowpid" 2>/dev/null || true
check "the slow new finished too" test -f "$W/.ntree/slow/deps/f"
printf '#!/bin/sh\nexit 1\n' > "$TMP/failbin/cp"; chmod +x "$TMP/failbin/cp"
check "new fails when the build fails" fails bash -c "cd '$W' && PATH='$TMP/failbin:$PATH' '$NTREE' new broken"
check "failed build leaves no worktree" test ! -e "$W/.ntree/broken"
check "failed build leaves no branch" fails git -C "$W" show-ref --verify --quiet refs/heads/broken
check "failed build leaves no state entry" bash -c "! jq -e '.workspaces.broken' '$W/.ntree/state.json' >/dev/null"

# --- Ctrl-C during run --rm still cleans up --------------------------------------
if command -v python3 >/dev/null 2>&1; then
  # ctrl_c_when <marker> <dir> <cmd...>: start cmd in its own process group,
  # wait until <marker> exists (no fixed sleeps: CI machines are slow), then
  # Ctrl-C the whole group like a terminal would.
  ctrl_c_when() {
    python3 - "$@" <<'EOF'
import os, signal, subprocess, sys, time
marker, cwd, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
p = subprocess.Popen(cmd, cwd=cwd, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
deadline = time.time() + 60
while not os.path.exists(marker) and time.time() < deadline and p.poll() is None:
    time.sleep(0.05)
time.sleep(0.2); os.killpg(p.pid, signal.SIGINT); p.wait(timeout=30)
EOF
  }
  ctrl_c_when "$TMP/intr-started" "$G" "$NTREE" run intr --rm -- "touch '$TMP/intr-started'; sleep 30"
  check "interrupted run --rm removes its workspace" test ! -e "$G/.ntree/intr"
  check "interrupted run --rm removes its branch" fails git -C "$G" show-ref --verify --quiet refs/heads/intr

  # Ctrl-C after the workspace is built but before the command starts (during setup).
  Q="$TMP/setupintr"; new_repo "$Q"; echo '.ntreerc' >> "$Q/.git/info/exclude"
  printf 'NTREE_SETUP_CMD=%q\n' "touch '$TMP/setup-started'; sleep 30" > "$Q/.ntreerc"
  ( cd "$Q" && "$NTREE" allow ) >/dev/null 2>&1 || true
  ctrl_c_when "$TMP/setup-started" "$Q" "$NTREE" run sx --rm -- true
  check "Ctrl-C during setup of run --rm removes the workspace" test ! -e "$Q/.ntree/sx"
  check "Ctrl-C during setup of run --rm removes the branch" fails git -C "$Q" show-ref --verify --quiet refs/heads/sx
fi

# --- two repos allocating ports at the same moment ----------------------------------
X1="$TMP/xr1"; X2="$TMP/xr2"; new_repo "$X1"; new_repo "$X2"
for i in 1 2 3 4 5 6; do
  ( cd "$X1" && "$NTREE" new "a$i" >/dev/null 2>&1 ) &
  ( cd "$X2" && "$NTREE" new "b$i" >/dev/null 2>&1 ) &
done; wait
check "parallel new in two repos never shares a port" \
  test -z "$( { jq -r '.workspaces[].ports[]' "$X1/.ntree/state.json"; jq -r '.workspaces[].ports[]' "$X2/.ntree/state.json"; } | sort | uniq -d)"

# --- Ctrl-C during new rolls back -------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  # the slow cp marks when the build is under way
  printf '#!/bin/sh\ntouch %q; sleep 30; exec %s "$@"\n' "$TMP/build-started" "$realcp" > "$TMP/slowbin/cp"
  PATH="$TMP/slowbin:$PATH" ctrl_c_when "$TMP/build-started" "$W" "$NTREE" new intr
  check "Ctrl-C during new leaves no worktree" test ! -e "$W/.ntree/intr"
  check "Ctrl-C during new leaves no state entry" bash -c "! jq -e '.workspaces.intr' '$W/.ntree/state.json' >/dev/null"
  check "Ctrl-C during new leaves no branch" fails git -C "$W" show-ref --verify --quiet refs/heads/intr
fi

# --- sync refuses an untrusted .ntreerc instead of dropping every link ----------
set_links 'ctx'
( cd "$L" && "$NTREE" new t1 ) >/dev/null 2>&1 || true
echo '# edited' >> "$L/.ntreerc"
check "sync refuses while .ntreerc is untrusted" fails bash -c "cd '$L' && '$NTREE' sync"
check "and the links are still there" test -L "$L/.ntree/t1/ctx"
( cd "$L" && "$NTREE" allow ) >/dev/null 2>&1 || true

# --- a branch checked out elsewhere; list shows the real branch -------------------
git -C "$V" branch side
git -C "$V/.ntree/nb" switch -q side
check "list shows the branch actually checked out" bash -c "cd '$V' && '$NTREE' list | grep '^nb ' | grep -q ' side '"
check "doctor mentions the switch" bash -c "cd '$V' && '$NTREE' doctor 2>&1 | grep -q \"'nb' was created for nb but is on side\""
check "new for a branch checked out in a workspace names that workspace" \
  bash -c "cd '$V' && '$NTREE' new side 2>&1 | grep -q \"ntree cd nb\""

# --- corrupt state: commands stop, doctor rebuilds it ------------------------------
before="$(jq -cS '[.workspaces | to_entries[] | {k: .key, p: .value.ports}] | sort_by(.k)' "$V/.ntree/state.json")"
printf '{"workspaces": {"nb": {"bra' > "$V/.ntree/state.json"
check "list refuses a corrupt state file" bash -c "cd '$V' && '$NTREE' list 2>&1 | grep -q 'unreadable'"
check "new refuses a corrupt state file" fails bash -c "cd '$V' && '$NTREE' new never"
( cd "$V" && "$NTREE" doctor ) >/dev/null 2>&1 || true
after="$(jq -cS '[.workspaces | to_entries[] | {k: .key, p: .value.ports}] | sort_by(.k)' "$V/.ntree/state.json" 2>/dev/null || true)"
check "doctor rebuilds the same workspaces and ports" test "$before" = "$after"
check "doctor keeps the corrupt copy" bash -c "ls '$V/.ntree/' | grep -q 'state.json.corrupt-'"

# --- descriptions -------------------------------------------------------------------
E="$TMP/desc"; new_repo "$E"
( cd "$E" && "$NTREE" new fix/x -m "fix the folder freeze" ) >/dev/null 2>&1 || true
check "new -m sets the description" bash -c "cd '$E' && test \"\$('$NTREE' desc fix-x)\" = 'fix the folder freeze'"
check "list shows it" bash -c "cd '$E' && '$NTREE' list | grep '^fix-x ' | grep -q 'fix the folder freeze'"
( cd "$E" && "$NTREE" desc fix-x "now: the real fix" ) >/dev/null 2>&1 || true
check "desc <name> <text> changes it" bash -c "cd '$E' && test \"\$('$NTREE' desc fix-x)\" = 'now: the real fix'"
( cd "$E" && "$NTREE" desc fix-x --clear ) >/dev/null 2>&1 || true
check "desc --clear removes it" bash -c "cd '$E' && test -z \"\$('$NTREE' desc fix-x)\" && '$NTREE' list | grep '^fix-x ' | grep -q ' - '"
( cd "$E" && "$NTREE" run sp -m "spike" -- true ) >/dev/null 2>&1 || true
check "run -m sets it when creating" bash -c "cd '$E' && test \"\$('$NTREE' desc sp)\" = spike"
( cd "$E" && "$NTREE" run sp -m "spike, round 2" -- true ) >/dev/null 2>&1 || true
check "run -m updates an existing workspace" bash -c "cd '$E' && test \"\$('$NTREE' desc sp)\" = 'spike, round 2'"
( cd "$E" && "$NTREE" desc sp "$(printf 'y%.0s' $(seq 1 80))" ) >/dev/null 2>&1 || true
check "list truncates a long description" bash -c "cd '$E' && '$NTREE' list | grep '^sp ' | grep -q 'yyy…'"
check "the full text is kept" bash -c "cd '$E' && test \"\$('$NTREE' desc sp | tr -d '\n' | wc -c | tr -d ' ')\" = 80"
check "desc on an unknown workspace fails" fails bash -c "cd '$E' && '$NTREE' desc nope hi"

# --- a new that fails before building still leaves .ntree/ ignored ----------------
F="$TMP/failearly"; new_repo "$F"
( cd "$F" && "$NTREE" new "$(git -C "$F" branch --show-current)" ) >/dev/null 2>&1 || true
check "a new that fails early leaves git status clean" test -z "$(git -C "$F" status --porcelain)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
