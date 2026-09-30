---
name: resolve-pr-comments
description: >-
  Walk through unresolved review comments on the open PR for the current branch.
  Explain each comment, wait for user approval on what to fix vs reply-only,
  then implement approved fixes, commit/push per comment, reply in Spanish,
  and resolve threads. Use when the user asks to resolve PR comments, address
  review feedback, handle code review threads, or run /resolve-pr-comments.
disable-model-invocation: true
---

# Resolve PR Comments

Interactive workflow to handle GitHub PR review feedback on the current branch.
**Do not jump straight into coding.** Explain each comment, wait for the user's
choices, then apply only what they approve.

## Hard rules

- **No code fixes until the user explicitly approves** which comments to solve
  (e.g. "resuelve 1 y 3", "arregla todos", "solo responde el 2").
- **PR thread replies are always in Spanish.**
- **Commit and push** approved code/doc fixes **before** (or immediately after)
  claiming something was fixed on the PR. Never say a PR issue is fixed if the
  commit is only local.
- **One commit per comment** (or one small commit for a tightly related group).
  No mega "fixes de revisión" commit.
- **No force-push** unless the user explicitly asks.
- Prefer **`gh`**. **Never invent** PR numbers, thread IDs, comment IDs, or URLs.
- If there is **no open PR** for the current branch, stop and tell the user.
- Align commit messages with project conventions when `AGENTS.md` (or similar)
  defines them — typically Spanish, granular commits starting with "Se …".

## Phase 1 — Find the PR

1. Confirm git state and branch:
   - `git --no-optional-locks status`
   - `git --no-pager branch --show-current`
2. Resolve the open PR for this branch:
   - `gh pr view --json number,title,url,state,labels,reviewDecision,headRefName`
3. If no open PR, **stop**. Do not continue.

## Phase 2 — Collect unresolved review threads

Use GraphQL so you get **thread IDs** (needed to resolve later). Prefer:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      url
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          diffSide
          comments(first:50) {
            nodes {
              id
              databaseId
              body
              author { login }
              createdAt
              url
            }
          }
        }
      }
    }
  }
}' -f owner=OWNER -f repo=REPO -F number=PR_NUMBER
```

Resolve `OWNER`/`REPO` via `gh repo view --json owner,name` (or parse
`gh pr view --json url`).

**Only work with unresolved threads** (`isResolved: false`). Skip resolved ones
unless the user asks to revisit them.

If GraphQL fails, fall back to `gh api` REST review comments, but still obtain
real IDs before attempting resolve/reply. Never guess IDs.

## Phase 3 — Report and assess (no code changes yet)

For each unresolved thread, present a numbered list entry with:

1. **Index** (1-based) for easy reference
2. **Location** — file path and line(s); note if outdated
3. **Author** — reviewer login
4. **What they asked** — concise paraphrase of the request/concern (quote brief
   key phrases when helpful)
5. **Recommendation** — one of:
   - **Worth fixing** — clear bug, correctness, security, or real improvement
   - **Misinterpretation** — reviewer misread the code; reply may be enough
   - **Intentional** — current behavior is deliberate; explain why
   - **Optional style** — nit/style; fix only if user wants
6. **Suggested plan or reply** — concrete fix steps, or a draft Spanish reply
   if no code change is warranted

Read the relevant code before assessing. Do not assess blind.

**Stop here.** Ask the user which items to:

- fix in code (and commit/push),
- reply only (no code),
- skip / leave open.

Do **not** implement anything until they answer.

## Phase 4 — Implement only approved items

After explicit approval (e.g. "resuelve 1 y 3"):

For each approved **fix**:

1. Make the minimal scoped change that addresses that comment.
2. Validate if practical (lint/tests relevant to the change).
3. **Commit** with a focused message (project commit style if defined).
4. **Push** to the PR branch (`git push`; no force unless asked).
5. **Reply in Spanish** on the thread, summarizing what changed (and commit
   short SHA if useful).
6. **Mark the thread resolved** via GraphQL:

```bash
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) {
    thread { id isResolved }
  }
}' -f threadId=THREAD_ID
```

For each approved **reply-only**:

1. Post a clear Spanish explanation (no code change).
2. Resolve the thread only if the user wants it closed; otherwise leave open.

### Replying on threads

Prefer replying in-thread with the real comment/thread identity, e.g.:

```bash
gh api repos/OWNER/REPO/pulls/PR_NUMBER/comments/COMMENT_DATABASE_ID/replies \
  -f body='Mensaje en español'
```

Or the GraphQL `addPullRequestReviewThreadReply` mutation when appropriate.
Use the **latest comment id in the thread** when required by the API.

Replies must be professional, concise Spanish. Examples of tone:

- Fix: «Listo, ajusté X para que Y. Quedó en el commit abc1234.»
- Intentional: «En este caso lo dejamos así porque Z; el comportamiento es intencional.»
- Misread: «El flujo actual ya cubre eso en W; no hizo falta cambiar código.»

## Phase 5 — Labels when done

When everything the user wanted handled is done:

1. Remove label `changes-requested` if present.
2. Add label `ready-for-review` if available on the repo.

```bash
gh pr edit PR_NUMBER --remove-label changes-requested
gh pr edit PR_NUMBER --add-label ready-for-review
```

Ignore errors if a label does not exist; do not fail the whole workflow for that.

## Phase 6 — Final summary

End with:

- PR link
- What was fixed (comment index + short description + commit hash)
- What was reply-only
- What was left alone / still open
- Label updates, if any

## Workflow checklist

```
- [ ] Identified open PR for current branch
- [ ] Loaded unresolved threads with real thread IDs
- [ ] Reported assessment for each comment
- [ ] Waited for user approval (no premature fixes)
- [ ] Implemented only approved fixes
- [ ] One commit per comment/group + push
- [ ] Spanish replies posted
- [ ] Threads resolved where appropriate
- [ ] Labels swapped when work requested is complete
- [ ] Summary delivered
```

## Anti-patterns

- Fixing all comments without asking
- One giant commit for the whole review
- Claiming "fixed on the PR" without push
- English replies on review threads (unless user explicitly demands English)
- Inventing thread/comment IDs
- Force-pushing to "clean up" review commits
- Expanding scope beyond the approved comments
