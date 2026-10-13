---
name: create-branch-for-task
description: Create a feature/fix/chore git branch for a task after confirming name and base branch with the user. Default base is develop (fetch/pull remote first); optionally create from the current branch. Use when the user asks to create a branch, start a task branch, or open work on a new branch before coding.
---

# Create Branch for Task

Create a new git branch for upcoming work. Confirm the branch name and base branch with the user before creating anything.

## When to use

Use this skill when the user asks to:

- create a branch for a task / ticket / feature
- start work on a new branch
- "create-branch-for-task", "branch for the task", or similar

Do not use this skill when the user wants branch + commit + PR in one flow (use `branch-commit-pr`), or only a commit/PR (`commit` / `create-pr`).

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
- Short and descriptive; no ticket noise unless the user supplies a ticket id
- Derive the slug from the user's task description or prior conversation context
- If the user gives a Spanish description, translate the intent into an English kebab slug
- Examples: `feature/user-search`, `fix/locker-date-validation`, `chore/update-eslint`

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

| Value              | Source                                      |
| ------------------ | ------------------------------------------- |
| Current branch | `HEAD`                                      |
| Proposed base  | `develop` by default, or user/current       |
| Working tree   | clean vs dirty (uncommitted changes)        |

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

| Field | Value |
| ----- | ----- |
| New branch | `feature/example-name` |
| Base branch | `develop` (default; will fetch + update from origin before creating) |
| Current branch | `<name>` |
| Working tree | clean, or dirty (list notable paths if dirty) |

Do you approve? You can change the branch name or the base: develop, current branch, or another.

Adjust the Base branch row when not using `develop`, for example:

- `current (feature/foo), will not update develop`
- `main (fetch + update from origin)`

Do not create the branch until the user confirms (they may edit name or base).

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

Do not commit, push, or open a PR in this skill unless the user separately asks (then use `commit`, `create-pr`, or `branch-commit-pr`).

### 6. Final report

Return a rendered markdown table:

| Result | Value |
| ------ | ----- |
| New branch | name, and that it is checked out |
| Base used | branch the new branch was created from |
| Fetch / fast-forward status | whether remote was fetched, whether base was fast-forwarded or skipped |
| Upstream tracking | tracking status, usually none yet because there was no push |
| Working tree status | status after the switch |
| Warnings | dirty tree carried over, skipped pull, or other warnings; use `None` if there are none |

## Important constraints

- Always confirm branch name and base branch before creating.
- Default base is `develop`, updated from remote before branch creation.
- Creating from current branch is allowed and common when requested or confirmed.
- Allowed prefixes only: `feature/`, `fix/`, `chore/`.
- Branch slug language: English only.
- Name comes from the task description the user gives or from conversation context, do not invent unrelated slugs.
- Never push unless the user explicitly asks after this skill.
- Never discard or reset user changes to "clean" the tree without an explicit ask.
- Never overwrite an existing branch without explicit approval.
- Leave the user on the new branch at the end.

## Failure shortcuts

| Situation                            | Action                                                |
| ------------------------------------ | ----------------------------------------------------- |
| No task context for a slug           | Ask what the branch is for, then propose a name       |
| Unknown prefix                       | Ask feature vs fix vs chore once                      |
| Local branch name already exists     | Propose another name; do not overwrite                |
| `develop` missing locally and remote | Report; ask for another base                          |
| `pull --ff-only` fails               | Stop; report divergence; ask how to proceed           |
| Dirty tree blocks checkout           | Report conflicts; offer stash or stay put             |
| User rejects plan                    | Do not create anything; wait for a revised plan       |

## Example confirmation (default develop)

| Field | Value |
| ----- | ----- |
| New branch | `feature/user-search` |
| Base branch | `develop` (default; will fetch + update from origin before creating) |
| Current branch | `develop` |
| Working tree | clean |

Do you approve? You can change the branch name or the base: develop, current branch, or another.

## Example confirmation (from current)

| Field | Value |
| ----- | ----- |
| New branch | `fix/locker-date-validation` |
| Base branch | `current (feature/lockers-api)`, no pull unless you ask |
| Current branch | `feature/lockers-api` |
| Working tree | dirty (`app/Models/Locker.php`) |

Do you approve?

After approval, update base if needed, run `git checkout -b <approved-name>`, then report.
