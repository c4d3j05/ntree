# ntree

Run multiple branches of the same repo in parallel — each in its own workspace
folder with its own port(s) and background dev server.

`ntree` is a thin layer over `git worktree`: each workspace is a real per-branch
checkout that shares one `.git` object store (history and blobs are never
duplicated), plus a small orchestrator for ports, per-workspace env, and process
lifecycle (`run -d` / `stop` / `list`). Every workspace is a plain folder, so
editors, LSPs, file watchers, and dev servers all work unmodified.

Dependencies are installed **correctly per branch** by your own package manager
via an optional setup command (`npm ci`, `uv sync`, …). For a big npm/yarn
`node_modules`, you can opt into instant **APFS copy-on-write** cloning instead.

macOS only (APFS copy-on-write is used for the optional dep cloning).

## Install

```bash
# From the tap (recommended):
brew tap c4d3j05/ntree https://github.com/c4d3j05/ntree
brew install ntree

# Or bleeding edge, no release required:
brew install --HEAD c4d3j05/ntree/ntree
```

Dependencies (`git`, `jq`) are installed automatically by Homebrew.

### Shell integration (optional, for `cd`)

To make `ntree <workspace>` change into the workspace directory, add the shell
function to your shell config (a binary can't `cd` its parent shell on its own):

```bash
echo 'eval "$(ntree shell-init)"' >> ~/.zshrc   # or ~/.bashrc
```

Then `ntree feature-login` (or `ntree cd feature-login`) drops you into that
workspace. Everything else passes straight through to ntree.

## Quick start

```bash
cd your-repo

# optional: set a setup command (e.g. `npm ci`), ports, default dev command
cp "$(brew --prefix)/share/ntree/.ntreerc.example" .ntreerc
$EDITOR .ntreerc && ntree allow   # .ntreerc is sourced as bash → trust it once

echo ".ntree/" >> .gitignore        # workspaces live here; don't commit them

ntree new feature-login                     # worktree + ports (+ runs setup if configured)

# Run a dev server in the background (detached, tracked by pid):
ntree run feature-login -d -- npm run dev   # remembers the command
ntree run feature-login -d                  # later: reuses the remembered command
ntree stop feature-login

# Or run a one-off command in the foreground (streams output, returns exit code):
ntree run feature-login --rm -- npm test    # create, run tests, tear down
ntree run hotfix -- npm run build           # keep the workspace to inspect after
ntree list                       # see branches, ports, running status
ntree open feature-login         # open the folder in your editor
ntree stop feature-login
ntree rm feature-login           # tear it down (prompts unless --force)
```

## Commands

| Command | Description |
|---|---|
| `ntree new <branch> [--from <base>] [--ports <n>]` | Create a workspace: git worktree + assigned port(s), then run `NTREE_SETUP_CMD` (if set) to install deps. Creates the branch if it doesn't exist. `--ports` overrides how many ports to reserve for this workspace. |
| `ntree run <branch> [--from <base>] [-d] [--rm] -- <cmd...>` | Run a command in the workspace's worktree (creates it if needed). **Foreground** (default): streams + logs output, exits with the command's code; `--rm` tears the workspace down afterward. **`-d`/`--detach`**: runs in the background tracked by pid, for dev servers. Remembers the command per workspace, so a later bare `ntree run <name> -d` reuses it. Logs to `.ntree/<name>/ntree.log`. |
| `ntree list` | Show the root checkout plus all workspaces, branches, ports, and live status. |
| `ntree stop <name>` | Stop the detached (`run -d`) process **and reclaim the workspace's ports** — also kills any server still listening from inside the worktree, on *any* port (e.g. a `npm run dev` you launched by hand, or a dev server that auto-picked its own port). Only TCP listeners are targeted, so a shell you `cd`'d in is spared, as is any listener whose working dir is outside the worktree. |
| `ntree open <name>` | Open the folder in `$EDITOR` / VS Code / Finder. |
| `ntree <name>` / `ntree cd <name>` | `cd` into the workspace (needs [shell integration](#shell-integration-optional-for-cd)). `ntree path <name>` prints its path. |
| `ntree git <name> <args...>` | Run any git command in that workspace's worktree (e.g. `ntree git feature-a status`, `ntree git feature-a push -u origin feature-a`). Exits with git's code. |
| `ntree sync-deps [<name>]` | Refresh a workspace's deps (or all): re-run `NTREE_SETUP_CMD` and re-clone any `NTREE_CLONE_DIRS`. Use after a lockfile change in `main`. |
| `ntree rm <name> [--force]` | Stop, kill any server still running in the worktree (same scoped kill as `stop`), remove the worktree, delete the folder. |
| `ntree doctor` | Verify APFS/git, clear stale locks, prune workspaces whose worktree vanished, flag deleted branches and orphan folders, reconcile PIDs. |
| `ntree allow` | Trust this repo's `.ntreerc` so it gets loaded (re-run after edits). |
| `ntree version` | Print the version. |

Branch names with `/` map to a workspace name with `-` (e.g. `feat/login` →
`feat-login`).

## Configuration

`.ntreerc` is **entirely optional** — ntree works with zero config: `ntree run`
takes any command, and `ntree run <name> [-d] -- <cmd>` remembers its command per
workspace. Use `.ntreerc` only to set project-wide defaults. Because it is
**sourced as bash**, ntree won't load it until you trust it with `ntree allow`
(re-run after edits). See [`.ntreerc.example`](.ntreerc.example):

```bash
NTREE_SETUP_CMD='npm ci'             # run on `new` to install deps (correct per branch)
# NTREE_START_CMD='npm run dev'      # optional default command for bare `ntree run`
NTREE_PORT_RANGE_START=3001          # first port to try
NTREE_PORT_RANGE_END=3099            # last port to try
NTREE_PORT_COUNT=1                   # ports reserved per workspace
# NTREE_PORTS='API FRONTEND'         # optional: name the ports → API_PORT, FRONTEND_PORT
#                                    #   (its length sets the count; PORT/PORT2 still work)
# NTREE_CLONE_DIRS='node_modules'    # opt-in: COW-clone deps from main instead of setup
```

**Deps: setup vs. clone.** By default `new` only makes the worktree. Set
`NTREE_SETUP_CMD` (e.g. `npm ci`, `pnpm i`, `uv sync`, `bundle install`) and
ntree runs it in each new workspace — your package manager installs exactly what
the branch's lockfile specifies. `NTREE_CLONE_DIRS` is an **opt-in** speed hack:
it COW-clones those dirs from `main` (instant, ~0 disk) but is a *snapshot* that
can be stale, so it only suits a big npm/yarn `node_modules`. Don't clone `.venv`
(absolute paths) or a pnpm/Bun `node_modules` (already globally deduped) — use
`NTREE_SETUP_CMD` for those.

> Quote `$PORT` with **single** quotes in `.ntreerc` or on the `run`
> command line (`'... --port $PORT'`) so it expands at run time, not when the
> config is read.

### Works with any stack

The tool is language-agnostic — you supply the setup and run commands. Examples:

| Stack | `NTREE_SETUP_CMD` | Run |
|---|---|---|
| Node / Nuxt / Rails | `npm ci` | `ntree run web -d -- npm run dev` (read `$PORT`) |
| Vue (Vite) | `npm ci` | `ntree run web -d -- 'npm run dev -- --port $PORT'` |
| pnpm | `pnpm i` | `ntree run web -d -- pnpm dev` |
| Python + uv | `uv sync` | `ntree run web -d -- 'uv run flask --app app run -p $PORT'` |
| Python + poetry | `poetry config virtualenvs.in-project true --local && poetry install` | `ntree run web -d -- 'poetry run python manage.py runserver 0.0.0.0:$PORT'` |
| Django (pip/venv) | `python -m venv .venv && .venv/bin/pip install -r requirements.txt` | `ntree run web -d -- '.venv/bin/python manage.py runserver 0.0.0.0:$PORT'` |
| Rust | *(none)* | `ntree run web -d -- cargo run` |

#### Python (uv / poetry)

Python is the case the setup model handles best: `uv`/`poetry` build a real venv
**inside the worktree**, correct for the branch's lockfile — no cloning (venvs
hardcode absolute paths and can't be copied).

- **uv** — `NTREE_SETUP_CMD='uv sync'` creates `.venv` in the workspace; run tools
  with `uv run …`. uv hardlinks from its global cache, so each per-workspace venv
  costs almost nothing on disk.
- **poetry** — set `virtualenvs.in-project true` (as above) so `.venv` lives in
  the worktree and is removed by `ntree rm`. Without it, poetry stores the venv in
  a central cache keyed by path — each workspace still gets its own, but `ntree rm`
  won't clean it up. Run tools with `poetry run …`.

Working on a node repo and a python repo at once just means running ntree in
each — every repo has its own `.ntree/` state and (optional) `.ntreerc`. Stateful
apps (Django/Rails) should namespace their DB with `$NTREE_WORKSPACE` so parallel
workspaces don't collide.

### Per-workspace environment

`ntree run` sources `<workspace>/.env.workspace`, which ntree writes with:

- `NTREE_WORKSPACE` — the workspace name; use it as a stable isolation key,
  e.g. `docker compose -p "$NTREE_WORKSPACE" up`, or a per-workspace database
  name like `myapp_$NTREE_WORKSPACE`. This is how you keep parallel workspaces
  from colliding on a shared DB/service (ntree gives you the key; wiring it into
  your app/compose is up to you).
- `PORT`, and `PORT2`, `PORT3`, … when more than one port is reserved (for apps
  that need several — e.g. a backend + frontend). Set the count per repo with
  `NTREE_PORT_COUNT`, or per workspace with `ntree new <branch> --ports <n>`.
  Name them with `NTREE_PORTS='API FRONTEND'` to also get `API_PORT`/`FRONTEND_PORT`
  aliases. Ports are re-validated when a `run -d` server launches and reallocated
  if another process grabbed one in the meantime.

> After a lockfile change in `main`, refresh a workspace with
> `ntree sync-deps <name>` (re-runs setup / re-clones).

## How it works

```
repo/               # your main checkout
.ntree/
  state.json        # workspace registry (name, branch, path, ports, pid, cmd)
  feature-login/    # a git worktree — its own working dir, shared .git
  feature-billing/  # another one, on a different branch and port
```

- **git worktree** gives each branch a real working directory that shares the
  one `.git` object store — history and blobs are never duplicated.
- **deps** are installed per workspace by `NTREE_SETUP_CMD` (correct for the
  branch), or optionally **APFS copy-on-write** cloned from `main` (instant, and
  unchanged files share disk blocks) when `NTREE_CLONE_DIRS` is set.

### Disk cost per extra workspace

| Item | Cost |
|---|---|
| Git history / objects | 0 (shared via worktree) |
| Checked-out source | small (usually MBs) |
| Deps (`node_modules`, etc.) | full install by default; ~0 with opt-in COW clone (grows only as files diverge) |
| Build output | per-workspace (intentionally isolated) |

## Development

```bash
bash -n bin/ntree     # syntax check
./bin/ntree doctor    # environment check
```

## License

MIT
