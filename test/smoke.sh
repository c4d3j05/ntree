#!/usr/bin/env bash
# Smoke tests for ntree against throwaway repos. Run: test/smoke.sh
set -euo pipefail

NTREE="$(cd "$(dirname "$0")/.." && pwd)/bin/ntree"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/config"   # keep the .ntreerc allow-list out of the real one

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
( cd "$R" && "$NTREE" new feat/a ) >/dev/null 2>&1
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

# --- doctor repairs an exclude line glued by older versions -------------------
printf 'UserInterfaceState.xcuserstate.env.workspace\n' >> "$R/.git/info/exclude"
( cd "$R" && "$NTREE" doctor ) >/dev/null 2>&1 || true
check "doctor splits the glued pattern" grep -qx 'UserInterfaceState.xcuserstate' "$R/.git/info/exclude"
check "doctor leaves no glued line behind" fails grep -q '.\.env\.workspace$' "$R/.git/info/exclude"

# --- rm ------------------------------------------------------------------------
( cd "$R" && "$NTREE" rm feat-a --force ) >/dev/null 2>&1
check "rm removes the worktree" test ! -e "$R/.ntree/feat-a"

# --- linked paths ----------------------------------------------------------------
L="$TMP/linked"; new_repo "$L"
echo t > "$L/tracked.md"; git -C "$L" add tracked.md
git -C "$L" -c user.name=t -c user.email=t@t commit -q -m tracked
echo '.ntreerc' >> "$L/.git/info/exclude"
mkdir -p "$L/ctx" "$L/.claude"; echo spec > "$L/ctx/a.md"; echo '{}' > "$L/.claude/settings.local.json"
set_links() {  # set_links <NTREE_LINK_PATHS> [extra .ntreerc line]
  printf "NTREE_LINK_PATHS='%s'\n%s\n" "$1" "${2:-}" > "$L/.ntreerc"
  ( cd "$L" && "$NTREE" allow ) >/dev/null 2>&1
}
set_links 'ctx .claude/settings.local.json'
( cd "$L" && "$NTREE" new w1 ) >/dev/null 2>&1
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
( cd "$L" && "$NTREE" sync w1 ) >/dev/null 2>&1
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
( cd "$L" && "$NTREE" rm w1 --force ) >/dev/null 2>&1
check "rm keeps the link source" test -f "$L/ctx/a.md"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
