# GitPulse — MCP Server PRD

## Problem Statement

Developers and agents working across workspaces with one or many git repos lack a unified, safe way to scan, diagnose, and sync repositories. Manual `git pull` is error-prone — conflicts get force-resolved, forks drift from upstream, submodules go stale, and there's no audit trail. There is no tool that combines workspace-wide repo discovery with cautious, user-confirmed sync operations exposed as composable MCP tools.

## Objective

Build **GitPulse**, an MCP server that uses the GitHub CLI (`gh`) and `git` to provide workspace-aware repository scanning, health diagnostics, and safe pull/sync operations. All destructive operations require explicit user confirmation. All artifacts GitPulse produces are gitignored automatically.

## In Scope

- Deep recursive workspace scanning to discover all git repos (including submodules)
- Per-repo and workspace-wide health diagnostics
- Safe pull operations with conflict strategy selection
- Fork detection and upstream sync
- Scan result caching with audit trail for agent consumption
- Structured JSON output (caller renders)
- Auto-management of `.gitignore` entries for GitPulse artifacts
- Configurable ignore patterns for scan (skip `node_modules`, `.cache`, etc.)
- Workspace root auto-detection (find repo root from cwd, accept optional override)

## Out of Scope

- Push operations (this is a read/pull tool, not a push tool)
- Branch creation or management
- Commit authoring
- CI/CD integration
- GitHub API operations beyond what `gh` provides for repo/fork info
- Scheduled/cron execution (on-demand only)

## Critical User Journeys

### Journey 1: First-time workspace scan
User (or agent) invokes `scan_workspace` → GitPulse recursively discovers all repos → returns structured map of repos with remotes, branches, submodule relationships → caches result to `.gitpulse/cache/scan.json` → adds `.gitpulse/` to `.gitignore` if not present.

### Journey 2: Workspace health check
User invokes `diagnose_workspace` → GitPulse checks every discovered repo for: uncommitted changes, ahead/behind remote, detached HEAD, stale branches, broken remotes, submodule drift, fork upstream drift, large untracked files, `gh` auth issues → returns structured diagnostic report → caches to `.gitpulse/cache/diagnosis.json`.

### Journey 3: Safe pull
User invokes `pull_repo` for a specific repo → GitPulse checks status → if clean fast-forward: reports what will change, asks confirmation → pulls → returns result. If conflicts or dirty state: reports the situation, presents options (stash+pull, abort, force — with force requiring explicit confirmation), waits for user decision.

### Journey 4: Batch sync (clean repos)
User invokes `pull_repo` with batch mode after a diagnosis → GitPulse filters to repos that are clean and behind remote → confirms the batch list with user → executes fast-forward pulls → reports per-repo results.

### Journey 5: Fork sync
User invokes `sync_fork` → GitPulse detects upstream remote → compares local to upstream → reports divergence → user confirms → fetches upstream and merges/rebases per user choice.

## Functional Requirements

| Priority | Requirement | Acceptance Criteria |
|----------|-------------|---------------------|
| P0 | Deep recursive repo discovery | Finds all `.git` dirs including submodules, regardless of nesting depth |
| P0 | Repo status reporting | Returns: dirty files, ahead/behind counts, current branch, detached state, remote URLs |
| P0 | Safe pull with confirmation | Never force-overwrites without explicit user confirmation; fast-forward pulls report changes before executing |
| P0 | Structured JSON output | All tools return structured JSON; no human-formatted text in responses |
| P0 | Destructive op confirmation | Force pulls, stash drops, branch deletions always require explicit confirmation |
| P1 | Workspace diagnosis | Full health report: uncommitted, ahead/behind, detached HEAD, stale branches, broken remotes, submodule drift, fork drift, large untracked, auth issues |
| P1 | Scan caching | Cache scan results to `.gitpulse/cache/`; invalidate on re-scan; include timestamps |
| P1 | Audit trail | Log all operations to `.gitpulse/audit/` with timestamps, inputs, outputs, decisions |
| P1 | Auto-gitignore | On first run, ensure `.gitpulse/` is in workspace `.gitignore` |
| P1 | Fork detection and upstream sync | Detect fork repos via `gh`, offer upstream sync with merge/rebase choice |
| P1 | Configurable ignore patterns | Accept patterns to skip during scan (default: `node_modules`, `.cache`, `__pycache__`, `.venv`, `venv`, `vendor`) |
| P2 | Submodule status | Report submodule sync state relative to parent's pinned commit |
| P2 | Batch clean-pull | Batch fast-forward pull for repos with no dirty state and no conflicts |
| P2 | Workspace root detection | From cwd, walk up to find nearest `.git` root; fall back to cwd if none found |
| P2 | `gh` auth validation | Check `gh auth status` and report issues before operations that need it |

## Technical Decisions

- **Runtime**: Python 3.10+ (minimal deps, subprocess calls to `git` and `gh`)
- **MCP SDK**: `mcp` Python package (official MCP SDK)
- **Dependencies**: `gh` CLI (required, documented), `git` (required)
- **CLI usage strategy**:
  - `git` — all local operations: status, pull, fetch, diff, log, stash, branch, submodule. Faster, no network overhead for local state.
  - `gh` — all GitHub-specific operations: auth validation (`gh auth status`), fork detection (`gh repo view --json isFork,parent`), remote repo validation (`gh repo view`), upstream identification, repo metadata. `gh` is the single source of truth for GitHub auth — no manual token management.
  - Rule: if the data exists locally, use `git`. If it requires GitHub API context, use `gh`.
- **Installation path**: `.kiro/mcp/gitpulse/` — co-located with the Kiro agent infrastructure so Pickle Rick and all subagents can invoke it directly
  - `.kiro/mcp/gitpulse/server.py` — MCP server entrypoint
  - `.kiro/mcp/gitpulse/requirements.txt` — Python dependencies
  - `.kiro/mcp/gitpulse/README.md` — usage docs
- **MCP registration**: Registered in `.kiro/settings/mcp.json` so Kiro auto-discovers it
- **Runtime artifact storage**: `.gitpulse/` directory at workspace root (NOT in `.kiro/`)
  - `.gitpulse/cache/` — scan and diagnosis caches
  - `.gitpulse/audit/` — operation logs
  - `.gitpulse/config.json` — user ignore patterns, preferences
- **All `.gitpulse/` contents auto-added to `.gitignore`**
- **Separation of concerns**: Code lives in `.kiro/mcp/gitpulse/`, runtime data lives in `.gitpulse/` — code is version-controlled with the agent setup, runtime artifacts are gitignored

## MCP Tool Definitions

### `scan_workspace`
- **Params**: `path` (optional, default cwd), `max_depth` (optional, default unlimited), `ignore_patterns` (optional, overrides defaults)
- **Returns**: `{ repos: [{ path, remotes: [{name, url}], branches: [{name, tracking, ahead, behind}], current_branch, is_submodule, parent_repo, is_fork, upstream_remote }], cached_at, scan_duration_ms }`
- **Side effects**: Writes cache, ensures `.gitignore` entry

### `diagnose_workspace`
- **Params**: `path` (optional), `use_cache` (optional, default true — use cached scan if fresh)
- **Returns**: `{ repos: [{ path, issues: [{ type, severity, detail }] }], summary: { total_repos, healthy, warnings, errors }, diagnosed_at }`
- **Side effects**: Writes diagnosis cache and audit log

### `repo_status`
- **Params**: `repo_path` (required)
- **Returns**: `{ path, current_branch, detached, dirty_files: [{path, status}], ahead, behind, stashes, submodules: [{path, expected_commit, actual_commit, synced}], remotes, is_fork, upstream }`

### `sync_report`
- **Params**: `repo_path` (required), `include_upstream` (optional, default true for forks)
- **Returns**: `{ path, local_ref, remote_ref, commits_behind: [{sha, message, author, date}], commits_ahead: [{...}], upstream_behind: [{...}], fast_forward_possible, conflicts_likely }`

### `pull_repo`
- **Params**: `repo_path` (required), `branch` (optional, default current), `strategy` (optional: `ff_only`, `merge`, `rebase`, `force` — default `ff_only`), `stash_first` (optional, default false), `batch` (optional, list of repo paths for batch mode)
- **Returns**: `{ success, repos: [{ path, result, commits_pulled, files_changed, strategy_used, warnings }] }`
- **Confirmation required**: Always for `force`; first-time for batch; per-repo if conflicts detected

### `sync_fork`
- **Params**: `repo_path` (required), `strategy` (optional: `merge`, `rebase` — default `merge`), `branch` (optional, default main/master)
- **Returns**: `{ success, upstream_remote, commits_synced, conflicts, result }`
- **Confirmation required**: Always

## Assumptions

- `git` is installed and available on PATH
- `gh` CLI is installed and authenticated (`gh auth status` passes)
- Workspace has at least one git repo (otherwise scan returns empty)
- User has read access to all repos in workspace
- File system supports symlinks (for submodule detection)

## Risks → Mitigations

| Risk | Mitigation |
|------|------------|
| Deep scan on huge filesystem is slow | Default ignore patterns skip known junk dirs; caching avoids re-scan; max_depth param available |
| Force pull causes data loss | Force strategy always requires explicit confirmation; audit log records the decision |
| `gh` auth expires mid-operation | Validate auth before any `gh`-dependent operation; return clear error with fix instructions |
| Submodule state is complex | Report status only; don't auto-fix submodule drift without explicit user request |
| Cache goes stale | Include timestamps; `use_cache: false` forces fresh scan; diagnosis re-scans if cache older than configurable threshold |
| Multiple agents call simultaneously | File-level locking on `.gitpulse/` write operations; read operations are safe |
