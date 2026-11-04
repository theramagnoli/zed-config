---
name: review-branch
description: Trigger when the user asks to review a branch, check code before a PR, audit branch changes, or run /review-branch.
---

# Review Branch

Review the changes in the current branch against its base branch. Report correctness issues, quality problems, and inconsistencies. Read-only: never edit, commit, or push.

## When to use

Use this skill when the user asks to:

- review a branch before a PR
- check the code, audit changes, or look for problems in the branch
- "review-branch", "review my branch", "check before PR", or similar

Do not use this skill when the user wants to fix review feedback on an existing PR (`resolve-pr-comments`), create commits (`commit`), or open the PR (`create-pr`).

## Goal

1. Identify the base branch (default detection below, confirmed by the user).
2. Confirm branch + base + scope with the user before reviewing.
3. Review the full branch diff in context (read files, callers, history as needed).
4. Report findings ordered by severity with file, line, and concrete suggestion.

## Process

### 1. Inspect repo state

From the project root, run:

- `git --no-optional-locks status`
- `git --no-pager branch --show-current`
- `git --no-pager branch -vv`
- `git --no-pager log --oneline @{upstream}..HEAD` (if upstream exists)
- `git --no-pager diff --stat @{upstream}...HEAD` (or against candidate base)

Record:

| Value          | Source                                   |
| -------------- | ---------------------------------------- |
| Current branch | `HEAD`                                   |
| Candidate base | upstream, or `develop` / `main` fallback |
| Working tree   | clean vs dirty (uncommitted changes)     |

Hard stop if the repo is in bisect/rebase/merge conflict: report and ask how to proceed.
Hard stop if on the base branch itself (`main`, `master`, `develop`) with no feature branch: report and ask which branch to review.

### 2. Identify the base branch

Pick the candidate base in this order:

1. Upstream tracking branch (`@{upstream}`) when it exists.
2. `develop` when it exists locally or as `origin/develop` and the current branch looks cut from it.
3. Repo default otherwise (`main` or `master`; check `gh repo view --json defaultBranchRef` when available).

Never guess silently. The candidate base always goes through the approval gate below.

### 3. Approval gate (mandatory)

Show the plan as a rendered markdown table and wait for explicit approval before reviewing:

| Field   | Value                                              |
| ------- | -------------------------------------------------- |
| Branch  | current branch name                                |
| Base    | candidate base branch name                         |
| Scope   | N commits, +X -Y vs base, M files changed         |
| Working | clean, or dirty listing paths excluded from review |

Get scope numbers with `git --no-pager log --oneline <base>..HEAD` and `git --no-pager diff --shortstat <base>...HEAD`.

If the working tree is dirty, state that uncommitted changes are excluded unless the user asks to include them. Do not review unstaged work by default.

Do not start the review until the user confirms branch + base. Never ask with interactive prompts or dialogs: ask in the same message, in plain text, and let the user reply or correct any field in chat.

### 4. Collect the diff

After approval, load the full change set:

- `git --no-pager diff <base>...HEAD --stat`
- `git --no-pager diff <base>...HEAD` (per file as needed)
- `git --no-pager log --oneline <base>..HEAD` for commit-level context

For large branches, group files by area and review each group in context. Read the full file for every changed hunk, not just the diff lines.

### 5. Investigate in context

Dig deeper than the diff text:

- Read each changed file plus its callers and anything downstream the change touches.
- Use `git blame` and `git log` on suspicious lines to learn whether the code is new or inherited. Do not flag pre-existing code outside the branch diff unless the branch interacts with it.
- Before concluding a concern is real, check whether it is already handled elsewhere (a guard, validation at a higher layer, an existing test).
- Prefer evidence over speculation: run the relevant tests or linter when cheap, or note the exact reproduction to try.

### 6. Report, do not fix

This skill is read-only. Report findings and stop. Do not edit files, commit, push, or open a PR. Offer to fix as a follow-up only after the report.

## Review dimensions

Check every changed hunk against all of these:

| Dimension | What to look for |
| --------- | ---------------- |
| Correctness | Bugs, broken edge cases, wrong conditionals, off-by-one, null/undefined access, unhandled errors, race conditions, security issues (injection, auth gaps, exposed secrets) |
| Duplicated logic | Copy-pasted blocks, repeated conditionals, logic that already exists in a helper or another branch file |
| Naming | Vague or misleading variable, function, class, or file names (`data`, `tmp`, `handle`, `utils2`); names that lie about type or behavior; inconsistent casing or terminology |
| Comments | Redundant comments that restate the code, stale comments contradicting the change, missing comments on non-obvious intent or tradeoffs, commented-out code left behind |
| Consistency | Style, patterns, or conventions that differ from surrounding code or the repo (`AGENTS.md` when present): error handling, return shapes, imports, formatting, logging |
| Structure | Dead code, unused imports/params/exports, overlong functions, poor separation that makes the change harder to follow |
| Tests | New behavior without coverage where the repo normally tests, tests that mirror the implementation instead of the behavior, broken or skipped tests |

Do not pad the report with praise, summaries of what the branch does well, or generic advice. Only concrete findings tied to a file and line.

## Severity levels

Assign exactly one per finding:

| Severity | Meaning |
| -------- | ------- |
| `Critical` | Likely bug, security issue, data loss, or breakage. Must fix before PR. |
| `Major` | Duplicated logic, misleading naming, or inconsistency that will confuse or rot. Should fix before PR. |
| `Minor` | Redundant/stale comment, small naming or style slip, dead code. Fix if quick. |
| `Nit` | Trivial preference with no behavior or clarity gain. Fix only if touching the line anyway. |

If a suspected issue cannot be confirmed from the code, mark it `Minor` at most and say what evidence would confirm it.

## Final report

End with a rendered markdown summary, ordered Critical first, then Major, Minor, Nit. If no issues, say so in one line and stop.

| File | Line | Severity | Issue | Suggestion |
| ---- | ---- | -------- | ----- | ---------- |
| `app/Models/Locker.php` | 42 | Major | `data` hides that this is a validated reservation window | Rename to `reservationWindow` |
| `app/Services/Search.php` | 18 | Minor | Comment restates the next line | Delete comment |

Rules:

- One row per finding. Keep Issue and Suggestion to one line each.
- File paths relative to repo root, with backticks. Line numbers from the new side of the diff.
- Close with a single verdict line: `Verdict: ready for PR`, `Verdict: fix Critical/Major first`, or `Verdict: needs discussion` (when a finding depends on product/design intent).
- Offer one follow-up in plain text (fix findings, or proceed to `create-pr`). Do not act on it without being asked.

## Workflow checklist

```
- [ ] Current branch and candidate base identified; dirty paths noted
- [ ] Plan table shown; explicit approval received before reviewing
- [ ] Full branch diff reviewed in file context, not diff lines alone
- [ ] Every finding has file, line, severity, and concrete suggestion
- [ ] No edits, commits, or pushes made
- [ ] Verdict line delivered
```

## Anti-patterns

- Starting the review before the user confirms the base branch
- Flagging pre-existing code the branch does not touch
- Vague findings without a file, line, or concrete fix
- Rubber-stamping ("looks good") without checking callers and edge cases
- Expanding into a refactor instead of reporting
