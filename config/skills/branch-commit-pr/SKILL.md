---
name: branch-commit-pr
description: Take existing uncommitted workspace changes, create a feature/fix/chore branch from the current branch, commit with the commit skill, and open a PR back to the original base branch with the create-pr skill. Use when the user wants to ship one change set end-to-end (branch + commit + PR).
---

# Branch, Commit, and PR

End-to-end workflow: isolate current workspace changes on a new branch, commit them, and open a PR targeting the branch you started on.

## When to use

Use this skill when the user asks to:

- ship / branch / PR existing workspace changes in one flow
- create a `feature/`, `fix/`, or `chore/` branch from dirty work, commit, and open a PR
- "branch-commit-pr", "ship this change", or similar

Do **not** use this skill when the user only wants a commit, only a PR, or is already on the correct feature branch with commits ready (use `commit` or `create-pr` alone).

## Related skills (required)

This skill **orchestrates** existing skills. Load and follow them; do not reimplement their rules:

1. **`commit`** — granular Spanish `Se + verbo` commits
2. **`create-pr`** — Spanish PR title/description, profiles (`default` / `cam`), approval gate, `gh pr create`

Invoke them with the `skill` tool when you reach those steps.

## Goal

1. Remember the **starting branch** (PR base).
2. Create a new branch: `feature/*`, `fix/*`, or `chore/*`.
3. Commit the relevant uncommitted changes via **`commit`**.
4. Open a PR into the starting branch via **`create-pr`**.

## Process

### 1. Inspect and capture base branch

Run:

- `git --no-optional-locks status`
- `git --no-pager branch -vv`
- `git --no-pager rev-parse --abbrev-ref HEAD`
- `git --no-pager diff` and `git --no-pager diff --staged` as needed

Record:

| Value            | Source                                                               |
| ---------------- | -------------------------------------------------------------------- |
| **Base branch**  | Current branch name at start (e.g. `main`, `develop`, `feature/foo`) |
| **Working tree** | Untracked / unstaged / staged files that make up "the change"        |

**Hard stop** if there are **no** uncommitted changes and nothing staged: tell the user there is nothing to ship with this skill. (If they already have commits on a feature branch, point them to `create-pr`.)

**Hard stop** if the repo is in a bisect/rebase/merge conflict state: report and ask how to proceed.

### 2. Scope the change

- Default: ship **all** current uncommitted changes as one logical work unit on the new branch.
- If the working tree mixes unrelated work, either:
    - ask which paths belong to this ship, or
    - commit only the coherent subset and leave the rest unstaged (prefer asking when ambiguous).
- Do not discard, stash-drop, or revert user work.

### 3. Choose branch type and name

Prefix **must** be one of:

| Prefix     | When                                                    |
| ---------- | ------------------------------------------------------- |
| `feature/` | New behavior, UI, endpoint, capability                  |
| `fix/`     | Bug fix, incorrect behavior correction                  |
| `chore/`   | Tooling, deps, config, cleanup without product behavior |

Infer from the diff. If unclear, ask once.

**Name rules:**

- `feature|fix|chore/<short-kebab-description>`
- The slug **must be in English** (kebab-case). Do not use Spanish words in the branch name.
- Short and descriptive; no spaces; lowercase; ASCII only (no accents)
- No ticket noise unless the user supplies a ticket id
- Examples: `feature/user-search`, `fix/locker-date-validation`, `chore/update-eslint`
- Commit messages and PR title/body stay in **Spanish** (via `commit` / `create-pr`); only the branch name is English

If the user already gave a full branch name with a valid prefix:

- Use it if the slug is already English
- If the slug is Spanish or mixed, translate it to a clear English kebab slug and confirm in the approval plan

If a local branch with that name already exists, stop and ask for another name (do not overwrite).

### 4. Approval gate — branch plan (before switching)

Show and **wait for explicit approval** before creating the branch or committing:

- Base branch (PR target) = starting branch
- New branch name (`feature/` \| `fix/` \| `chore/` + slug)
- Files / change scope to include
- Intended commit approach (one commit vs several granular ones per `commit` skill)
- PR profile: `default` or `cam` (same rules as `create-pr`; ask once if unclear)

Do not create the branch, commit, push, or open a PR until the user approves this plan (they may edit the branch name or scope).

### 5. Create the branch

From a clean index perspective the uncommitted files should carry over on checkout -b:

```bash
git checkout -b feature/example-name
```

Use the approved name. Confirm with `git --no-pager rev-parse --abbrev-ref HEAD`.

If checkout fails because of conflicts with the branch switch, stop and report; do not force.

**Do not** commit on the base branch. **Do not** push until the create-pr step (after commit + PR plan approval).

### 6. Commit — use the `commit` skill

Load **`commit`** and follow it fully:

- Inspect diff on the new branch
- Small granular Spanish commits (`Se` + verbo)
- Stage only relevant files per commit
- No push in this step

After commits, `git --no-optional-locks status` should show a clean tree for the scoped work (or only left-out unrelated files still uncommitted, if that was agreed).

If commit fails, stop; do not open a PR.

### 7. Create PR — use the `create-pr` skill

Load **`create-pr`** and follow it fully, with these **overrides** for this workflow:

1. **Base branch** = the **starting branch** captured in step 1 (not necessarily `main`/`master`).
2. Current branch must be the new `feature/`/`fix/`/`chore/` branch with commits ahead of base.
3. Profile = the one approved in step 4 (`default` or `cam`), unless the user changes it at the PR approval gate.
4. Still run create-pr’s inspect steps, draft Spanish title + flat bullet description, and **second approval gate** (title, body, base, profile metadata) before push / `gh pr create`.
5. Push with `git push -u origin HEAD` only after that approval.
6. `gh pr create --base <starting-branch> ...` with profile flags from create-pr.

If create-pr would normally refuse because base is `main` and current is also default — that does not apply here: current is the new side branch and base is the recorded starting branch.

### 8. Final report

Return:

- New branch name
- Base branch (PR target)
- Commit subjects created
- PR URL
- Profile used
- Anything skipped (e.g. missing CAM label/reviewer)

## Important constraints

- **Never** commit directly on the original/base branch as part of this flow.
- **Never** push or `gh pr create` before the create-pr approval gate.
- **Never** invent commits or PR bullets not supported by the diff.
- **Never** delete or reset user changes to “clean” the tree without explicit ask.
- Prefer leaving the user on the **new** branch at the end (natural after the flow).
- If the user aborts mid-flow after branch creation but before PR, leave the branch as-is and report status; do not delete the branch unless they ask.

## Branch naming quick reference

```text
feature/<english-slug>   # new capability
fix/<english-slug>       # bugfix
chore/<english-slug>     # maintenance / tooling
```

Slug language: **English only** (e.g. `feature/user-search`, not `feature/busqueda-usuarios`).

## Failure shortcuts

| Situation                         | Action                                                              |
| --------------------------------- | ------------------------------------------------------------------- |
| No local changes                  | Stop; suggest `create-pr` if commits already exist on a side branch |
| Unrelated mixed diffs             | Ask which paths to include                                          |
| Unknown prefix                    | Ask feature vs fix vs chore once                                    |
| On base after failed checkout     | Do not commit; fix branch creation first                            |
| `gh` / network failure after push | Report branch remote URL and offer retry of PR only                 |
| User wanted draft title only      | Do not use full flow; use create-pr draft-only path                 |

## Example shape of the first approval message

```text
Plan branch-commit-pr
- Base (PR target): main
- New branch: feature/user-search
- Scope: app/Http/Controllers/UserController.php, resources/views/users/index.blade.php
- Commits: granular via commit skill
- PR profile: cam

¿Lo apruebas? (puedes cambiar nombre de rama, scope o perfil)
```

After approval → `git checkout -b ...` → `commit` skill → `create-pr` skill with `--base` = starting branch.
