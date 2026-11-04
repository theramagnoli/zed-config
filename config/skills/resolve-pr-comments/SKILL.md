---
name: resolve-pr-comments
description: Trigger when the user asks to resolve PR comments, address review feedback, handle code review threads, or run /resolve-pr-comments.
disable-model-invocation: true
---

# Resolve PR Comments

Work through the review feedback on the current branch's open PR. Dig into each
comment, decide on the merits whether it's worth acting on, then fix, rebut, or
skip it. Make the routine calls yourself and only come back to the user when
something is out of scope, ambiguous, or blocked.

## Hard rules

- Judge each comment yourself (fix vs rebut vs skip). See "When to stop and
  ask" for the cases where you should come back to the user instead.
- PR thread replies are always in Spanish.
- Commit and push a fix before (or immediately after) saying it's fixed on the
  PR. Never claim something is fixed while the commit is only local.
- One commit per comment, or one small commit for a tightly related group.
- No force-push unless the user explicitly asks.
- Prefer `gh`. Never invent PR numbers, thread IDs, comment IDs, or URLs.
- If there is no open PR for the current branch, stop and tell the user.
- Match the project's commit conventions when `AGENTS.md` (or similar) defines
  them, typically Spanish, granular commits starting with "Se …".

## Investigating

Dig deeper than the comment text:

- Read the full file, its callers, and anything downstream the change touches.
- Use `git blame` and `git log` to learn why the code is the way it is. A
  comment that would undo a deliberate decision or a recent fix needs stronger
  evidence than one pointing at fresh code.
- Prefer evidence over speculation: run the relevant tests or linter, or write
  a quick reproduction when you can.
- Before concluding a concern is real, check whether it's already handled
  elsewhere (a guard, validation at a higher layer, an existing test).
- Feel free to move around to investigate: check out `main`, `develop`, or
  another branch, compare implementations, look at other PRs and issues with
  `gh`. Always come back to the PR branch before editing, and never push or
  comment from an investigation branch.

### Subagents

- Spawn one subagent per non-trivial comment (or one per group when several
  comments target the same area). Brief it with the file path and line, the
  full comment text, the branch name, and what you need back: an
  evidence-based verdict from the categories below, the relevant code excerpts,
  and a concrete proposed action.
- Judge trivial comments yourself: obvious typos, renames, one-line fixes where
  the context is already clear.
- The final call and all edits are yours. Subagents never push, comment on the
  PR, or touch shared files.

## Judging comments

Treat every comment as a claim to verify, not an instruction to execute, and
back every verdict with something you actually read, ran, or found in history.

- **Separate the problem from the recommendation.** Reviewers (especially
  Copilot) often describe a real concern but attach a wrong or poor fix. If the
  problem is real, fix it your way instead of applying their diff, and say so
  in the reply with evidence.
- **Weigh edge cases by real probability.** A fix that only matters for input
  the system can never receive isn't worth extra branching. If handling it is
  nearly free and harmless (a guard clause), do it; otherwise rebut with why
  the case doesn't occur in practice.
- **Don't add tests just because they were asked.** Add one only if it catches
  a plausible regression, fits how the surrounding code is tested, and isn't a
  tautology. No test suite in that area, or a test that only mirrors the
  implementation back at itself, means skipping it and saying why.
- **Verdict categories** (also used in the final summary):
    - _Worth fixing_: clear bug, correctness, security, or real improvement.
    - _Real problem, bad recommendation_: the concern stands, the suggested fix
      doesn't; implement the better fix and explain it.
    - _Misinterpretation_: the reviewer misread the code or missed a guard
      elsewhere; rebut with the specific code path.
    - _Intentional_: current behavior is deliberate; explain why.
    - _Not worth it_: vanishingly rare edge case, unjustified extra test, no-op
      style nit, or complexity with no benefit. Rebut briefly only if it was
      explicitly demanded; otherwise a short factual note is enough.

## When to stop and ask

Come back to the user instead of pushing through when:

- The fix would spill past the comment's scope: other modules, API or
  signature changes, a real refactor rather than a small scoped edit.
- The comment is really a design, product, or process question that isn't
  yours to answer (like whether to support something at all).
- Reviews contradict each other, or two viable approaches have tradeoffs you
  can't settle from the code alone.
- You're blocked: failing tests you can't fix, intent that stays unclear
  after digging, missing access or credentials.
- The action is destructive or unusual (force-push, deleting content, changes
  outside the PR).

Keep it concrete: a couple of lines on the situation, the options you
considered, your recommendation, then resume on your own once answered.

## Phase 1 - Find the PR

1. Confirm git state and branch:
    - `git --no-optional-locks status`
    - `git --no-pager branch --show-current`
2. Resolve the open PR for this branch:
    - `gh pr view --json number,title,url,state,labels,reviewDecision,headRefName`
3. If no open PR, stop. If there are unrelated local changes, keep them out of
   the review-fix commits.

## Phase 2 - Collect unresolved review threads

Use GraphQL so you get the thread IDs needed to resolve later:

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

Get `OWNER`/`REPO` from `gh repo view --json owner,name` (or parse
`gh pr view --json url`). Work only with unresolved threads
(`isResolved: false`) unless the user asks to revisit resolved ones. If
GraphQL fails, fall back to REST review comments, but still get real IDs
first.

## Phase 3 - Investigate and judge

Work each comment (or coherent group) per the Investigating and Judging
sections above: subagent for the non-trivial ones, direct judgment for the
easy ones, exactly one verdict category each. Handle fixes first and replies
after, so rebuttals can reference what actually changed elsewhere.

## Phase 4 - Implement and reply

For each comment worth fixing:

1. Make the minimal scoped change that solves the real problem (your approach
   when the suggestion was poor).
2. Validate if practical (lint or tests covering the change).
3. Commit with a focused message, push to the PR branch, reply on the thread
   saying what changed and why (no commit SHAs in PR comments), then resolve
   the thread:

```bash
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) {
    thread { id isResolved }
  }
}' -f threadId=THREAD_ID
```

For each rebuttal: post a concise Spanish reply with the evidence, no code
change, and resolve the thread if the reply settles it (leave it open when it
invites real discussion).

Reply in-thread with the real comment identity:

```bash
gh api repos/OWNER/REPO/pulls/PR_NUMBER/comments/COMMENT_DATABASE_ID/replies \
  -f body='Mensaje en español'
```

(Or the GraphQL `addPullRequestReviewThreadReply` mutation when it fits; use
the latest comment id in the thread when the API requires it.)

### Reply tone

Factual, concise Spanish, in your replies and the final summary alike. No
pleasantries, no filler: the other side is usually another agent, not a
person. Don't apologize, thank, or say "good point". State what was done (or
why nothing was) and the evidence:

- Worth fixing: "Cambiado X a Y."
- Real problem, better fix: "El problema era real, pero se resolvió con Z en
  lugar de lo sugerido porque W."
- Intentional: "Se deja así porque Z."
- Misinterpretation: "El flujo ya cubre ese caso en W."
- Not worth it: "El caso no ocurre en la práctica porque W; se deja como está."

## Phase 5 - Labels when done

Once every comment is handled, remove `changes-requested` if present and add
`ready-for-review` if the repo has it:

```bash
gh pr edit PR_NUMBER --remove-label changes-requested
gh pr edit PR_NUMBER --add-label ready-for-review
```

Ignore errors for missing labels; don't fail the workflow over them.

## Phase 6 - Final summary

End with the PR link, then one compact table covering every comment, then any
label updates:

| #   | Verdict           | Action taken | Detail                             |
| --- | ----------------- | ------------ | ---------------------------------- |
| 1   | Worth fixing      | fix + push   | Short description plus commit hash |
| 2   | Not worth it      | rebut        | Why it was skipped                 |
| 3   | Misinterpretation | rebut        | Evidence posted                    |
| 4   | Worth fixing      | fix + push   | Commit hash                        |

State outcomes factually: commit hash, rebuttal reason, or why a thread was
left open.

## Workflow checklist

```
- [ ] Open PR identified; threads loaded with real IDs
- [ ] Every comment has an evidence-backed verdict
- [ ] Stopped for the user on anything out of scope or blocked
- [ ] Back on the PR branch; fixes committed and pushed
- [ ] Spanish replies posted; threads resolved where appropriate
- [ ] Labels swapped; summary table delivered
```

## Anti-patterns

- Letting clear-cut verdicts wait on the user instead of judging them
- Quietly expanding into a refactor instead of asking
- Pushing through blockers instead of asking
- Rubber-stamping a requested test or edge-case fix the code doesn't justify
- Pushing or replying from an investigation branch
