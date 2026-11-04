---
name: create-branch-for-task
description: Trigger when the user asks to create a branch, start a task branch, or open work on a new branch before coding.
---

# Create Branch for Task

Create a new git branch for upcoming work. Confirm the branch name and base branch with the user before creating anything.

## When to use

Use this skill when the user asks to:

- create a branch for a task / ticket / feature
- start work on a new branch
- "create-branch-for-task", "branch for the task", or similar

Do not use this skill when the user only wants a commit or a PR (`commit` / `create-pr`).

## Goal

1. Infer a branch name from the task description or conversation context.
2. Choose the base branch (default: `develop`).
3. Confirm name + base with the user.
4. Update the base from remote when applicable, then create and check out the branch.

## Branch naming rules

Prefix must be one of:

| Prefix     | When                                                    |
| ---------- | ------------------------------------------------------- |
| `feature/` | New behavior, UI, endpoint, capability                  |
| `fix/`     | Bug fix, incorrect behavior correction                  |
| `chore/`   | Tooling, deps, config, cleanup without product behavior |

Name format: `feature|fix|chore/<short-kebab-description>`

- Slug must be in English (kebab-case). Never Spanish words in the branch name.
- Lowercase ASCII only; no spaces, accents, or underscores
- Shape the slug as a short readable phrase (verb + object, 2-4 words), not a pile of keywords. Prefer dropping words over keeping them; if it takes more than 4 words, it is saying too much.
- Read the full branch name back before proposing it. It should sound like a short phrase (`fix/validate-locker-dates`), not a tag cloud (`fix/lockers-module-date-validation-bug`).
- No ticket noise unless the user supplies a ticket id
- Derive the slug from the user's task description or prior conversation context
- If the user gives a Spanish description, translate the intent into an English kebab slug
- Examples: `feature/user-search`, `fix/locker-date-validation`, `chore/update-eslint`
- Word pile vs readable: `feature/admin-users-table-search-pagination` becomes `feature/user-search`; `fix/lockers-module-date-validation-bug` becomes `fix/locker-date-validation`

If the user already supplies a full name with a valid prefix:

- Use it if the slug is already English
- If the slug is Spanish or mixed, propose an English kebab equivalent in the confirmation step

## Base branch rules

1. Default base: `develop`
    - Unless the user says otherwise, create the new branch from `develop`.
    - Before creating: fetch remote and update local `develop` with remote changes.
2. Current branch base
    - Also common: create from the branch the user is already on when they ask for that, or when they say "from here" / "from current".
3. Explicit base
    - If the user names another base (`main`, a feature branch, etc.), use that after confirmation.

Never create the branch from a stale local base when the agreed base is a remote-tracking branch you can update (especially `develop`).

## Process

### 1. Inspect repo state

From the project root, run:

- `git --no-optional-locks status`
- `git --no-pager branch -vv`
- `git --no-pager rev-parse --abbrev-ref HEAD`
- `git --no-pager remote show` / `git --no-pager branch -a` as needed to confirm `develop` exists locally or as `origin/develop`

Record:

| Value          | Source                                |
| -------------- | ------------------------------------- |
| Current branch | `HEAD`                                |
| Proposed base  | `develop` by default, or user/current |
| Working tree   | clean vs dirty (uncommitted changes)  |

Hard stop if the repo is in bisect/rebase/merge conflict: report and ask how to proceed.

Dirty working tree: uncommitted changes usually carry over on `git checkout -b` / `git switch -c`. If checkout might conflict, warn in the confirmation plan and ask whether to stash, commit first, or proceed anyway. Do not discard user changes.

### 2. Propose branch name and base

Infer:

- Prefix from task type (feature / fix / chore). If unclear, pick the best fit and note it in the plan, or ask once.
- Slug in English from the task text or conversation.
- Base: `develop` (default) unless the user asked for current branch or another base.

If a local branch with the proposed name already exists, propose a different name (do not overwrite or reset an existing branch).

### 3. Approval gate (mandatory)

Show the plan as a rendered markdown table and wait for explicit approval before any fetch/pull/checkout that creates the branch:

| Field       | Value                                                                |
| ----------- | -------------------------------------------------------------------- |
| New branch  | `feature/example-name`                                               |
| Base branch | `develop` (default; will fetch + update from origin before creating) |

The Base branch row must state which branch the new branch is created from. When that is not the current branch, say so in the row (e.g. `develop (not your current branch; will fetch + update from origin before creating)`). When it is the current branch, write `current (feature/foo), no pull unless you ask`.

If the working tree is dirty, add one line naming the paths that carry over. Otherwise say nothing about it.

Do not create the branch until the user confirms.

### 4. Update base from remote (when base is develop or another remote branch)

When the approved base is `develop` (or another branch that should track remote):

```bash
git fetch origin
```

Then update the local base. Prefer:

```bash
git checkout develop
git pull --ff-only origin develop
```

If `develop` does not exist locally but `origin/develop` does:

```bash
git checkout -b develop origin/develop
```

If `--ff-only` fails (local base diverged), stop and report; do not rebase or reset unless the user explicitly asks.

When the approved base is current branch and the user did not ask to update it from remote, skip pull unless they requested it. Optionally run `git fetch origin` only to inform, not to rewrite the current branch without approval.

### 5. Create and check out the branch

```bash
git checkout -b feature/example-name
```

Or equivalently:

```bash
git switch -c feature/example-name
```

Use the approved name. Create it from the approved base (HEAD must be on that base after step 4).

Confirm:

```bash
git --no-pager rev-parse --abbrev-ref HEAD
git --no-pager log -1 --oneline
```

If creation fails, stop and report; do not force (`-B` / reset) unless the user explicitly asks to replace a branch.

Do not commit, push, or open a PR in this skill unless the user separately asks (then use `commit` or `create-pr`).

Leave the user on the new branch at the end.

### 6. Final report

Return a rendered markdown table:

| Result                      | Value                                                                                  |
| --------------------------- | -------------------------------------------------------------------------------------- |
| New branch                  | name, and that it is checked out                                                       |
| Base used                   | branch the new branch was created from                                                 |
| Fetch / fast-forward status | whether remote was fetched, whether base was fast-forwarded or skipped                 |
| Upstream tracking           | tracking status, usually none yet because there was no push                            |
| Working tree status         | status after the switch                                                                |
| Warnings                    | dirty tree carried over, skipped pull, or other warnings; use `None` if there are none |

## Failure shortcuts

| Situation                            | Action                                          |
| ------------------------------------ | ----------------------------------------------- |
| No task context for a slug           | Ask what the branch is for, then propose a name |
| `develop` missing locally and remote | Report; ask for another base                    |
| User rejects plan                    | Do not create anything; wait for a revised plan |

## Example confirmation (default develop)

| Field       | Value                                                                                |
| ----------- | ------------------------------------------------------------------------------------ |
| New branch  | `feature/user-search`                                                                |
| Base branch | `develop` (not your current branch; will fetch + update from origin before creating) |

## Example confirmation (from current)

| Field       | Value                                                   |
| ----------- | ------------------------------------------------------- |
| New branch  | `fix/locker-date-validation`                            |
| Base branch | `current (feature/lockers-api)`, no pull unless you ask |

Working tree is dirty; `app/Models/Locker.php` carries over.

After approval, update base if needed, run `git checkout -b <approved-name>`, then report.
