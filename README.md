# 🔍 GitPulse

MCP server for workspace-aware git repo scanning, health diagnostics, and safe sync operations.

Built for [Kiro CLI](https://github.com/aws/kiro-cli) — works with any MCP-compatible client.

## What It Does

GitPulse uses `git` and GitHub CLI (`gh`) to give you (and your agents) a complete picture of every repo in your workspace, then safely sync them with user confirmation on anything destructive.

- **Scan** — deep recursive discovery of all git repos, including submodules
- **Diagnose** — full health check: dirty files, behind remote, detached HEAD, stale branches, broken remotes, submodule drift, fork drift, large untracked files, auth issues
- **Status** — deep single-repo status with fork and submodule awareness
- **Sync Report** — dry-run comparison of local vs remote (no changes made)
- **Pull** — safe pull with strategy selection (`ff_only`, `merge`, `rebase`, `force`) and batch support
- **Fork Sync** — sync forked repos with upstream

## Prerequisites

- Python 3.10+
- [git](https://git-scm.com/)
- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated via `gh auth login`
- [Kiro CLI](https://github.com/aws/kiro-cli) (or any MCP client)

## Install

```bash
git clone https://github.com/ecuadralmft/gitpulse.git
cd gitpulse
./install.sh
```

This will:
1. Copy the server to `~/.kiro/mcp/gitpulse/`
2. Create a Python venv and install dependencies
3. Register GitPulse in `~/.kiro/settings/mcp.json`

Restart Kiro CLI after install.

## Tools

| Tool | Description |
|------|-------------|
| `scan_workspace` | Deep recursive scan to discover all git repos |
| `diagnose_workspace` | Full health check across all discovered repos |
| `repo_status` | Deep status of a single repository |
| `sync_report` | Dry-run local vs remote comparison |
| `pull_repo` | Safe pull with conflict strategy and batch mode |
| `sync_fork` | Sync a forked repo with its upstream |

### Confirmation Policy

- **Read-only ops** (scan, diagnose, status, sync_report): no confirmation needed
- **Clean fast-forward pulls**: execute directly
- **Force pulls**: always require explicit `confirmed=True`
- **Fork sync**: always require explicit `confirmed=True`
- **Conflicts detected**: returns options for user to choose

## Architecture

- `git` handles all local operations (status, pull, fetch, diff, log, stash, branch, submodule)
- `gh` handles GitHub-specific operations (auth, fork detection, upstream identification, remote validation)
- Rule: if data exists locally → `git`. If it needs GitHub API → `gh`.

## Runtime Artifacts

GitPulse stores runtime data in `.gitpulse/` at the workspace root (auto-added to `.gitignore`):

```
.gitpulse/
├── cache/    # Scan and diagnosis caches
├── audit/    # Operation logs (JSONL, one file per day)
└── config.json  # User preferences
```

All operations are logged to the audit trail for consumption by other agents.

## File Structure

```
gitpulse/
├── mcp/
│   ├── server.py          # MCP server (all 6 tools)
│   └── requirements.txt   # Python dependencies
├── install.sh             # One-command installer
├── .gitignore
└── README.md
```

## License

MIT
