---
name: create-pr
description: Trigger when the user asks to open a PR, create a pull request, prepare PR details, or requests the CAM/CAM-UANL PR variant.
---

# Create PR

Create a pull request following these conventions.

## When to use

Use this skill when the user asks to open a PR, create a pull request, draft PR title and description, or publish a branch for review.

## Profiles (variants)

Choose one profile before drafting metadata. Shared steps (git inspect, title, description, approval gate, `gh pr create`) are the same. Only assignee, reviewer, and label differ.

| Profile   | When to use                                                            | Assignee        | Reviewer   | Label              |
| --------- | ---------------------------------------------------------------------- | --------------- | ---------- | ------------------ |
| `default` | User says "create a PR", "open PR", or does not mention CAM            | `@theramagnoli` | _(none)_   | _(none)_           |
| `cam`     | User says "create-pr-cam", "PR CAM", "CAM-UANL", or "ready-for-review" | `@theramagnoli` | `CAM-UANL` | `ready-for-review` |

### How to select the profile

1. If the user explicitly asks for the CAM flow, use `cam`.
2. If the user explicitly asks for a PR without reviewer or label, use `default`.
3. If unclear, ask once: default or CAM?
4. The approval plan records the chosen profile (see the `Profile` row in the Approval gate table).

## Process

1. Select the profile (`default` or `cam`) using the rules above.
2. Inspect git state before drafting anything:
    - `git --no-optional-locks status`
    - `git --no-pager branch -vv`
    - `git --no-pager log --oneline @{upstream}..HEAD` (or `main..HEAD` / `master..HEAD` if no upstream)
    - `git --no-pager diff --stat @{upstream}...HEAD` (or against the base branch)
3. If there are uncommitted changes, stop and either:
    - ask the user whether to commit first, or
    - use the `commit` skill when they want commits created
4. Confirm the current branch is not the base branch (`main` or `master`). If it is, stop and ask for a feature branch name.
5. Determine the base branch (`main` or `master`, or the repo default).
6. Draft the PR title and description from the overall changes in the branch (commits plus diff).
7. Show the PR plan as defined in Approval gate and get explicit approval before continuing.
8. After approval:
    - Push the branch if needed: `git push -u origin HEAD`
    - Create the PR with `gh` using a HEREDOC for the body
    - Apply only the metadata for the selected profile
9. Return the PR URL.

## PR title rules

- Write the title in Spanish
- Format: `Se <verbo> <feature> en <module>`
- Preferred verb forms in the title pattern: `Se agrega`, `Se modifica`, `Se elimina`, or another allowed verb (`implementa`, `corrige`, `actualiza`, `refactoriza`, `ajusta`, `integra`, `reemplaza`, `configura`)
- Describe the main outcome of the PR, not implementation details
- No trailing period
- No prefixes like `feat:`, `fix:`, `refactor:`, or `chore:`
- Do not use generic titles

### Title examples

```text
Se agrega búsqueda de usuarios en administración
```

```text
Se corrige validación de fechas en reservaciones de lockers
```

```text
Se integra autorización por grupos en secciones
```

## PR description rules

- Write the description in Spanish
- Use this exact body format:
    1. Prose overview: 2-4 simple Spanish sentences explaining what changed and why (the outcome, not implementation details)
    2. Blank line
    3. Flat bullet list of the concrete changes made
- Keep the prose simple and understandable. Avoid jargon and long explanations
- Open from the problem or motivation when there is one (what was broken, missing, or slow), then say what changed. Reserve the "Este PR…" opening for pure additions with no problem behind them
- Do not focus on commits. Describe the overall tasks completed in the PR
- Each bullet must be a concrete completed change
- Keep bullets concise and factual. Do not invent work that is not in the branch
- No titles or headings in the body

### Description examples

```text
Este PR agrega la búsqueda de usuarios en administración para localizar cuentas más rápido. Ahora se puede buscar por nombre y matrícula y la tabla muestra las coincidencias encontradas.

- Se agrega búsqueda de usuarios por nombre y matrícula
- Se normaliza el texto de búsqueda con unaccent
- Se actualiza la tabla de resultados para mostrar coincidencias
```

```text
Las reservaciones de lockers aceptaban fechas inválidas y quedaban en un estado inconsistente. Ahora las fechas se validan antes de guardar y los registros muestran el estado correcto.

- Se corrige validación de fechas en reservaciones de lockers
- Se actualiza cálculo del estado de los registros de lockers
```

## Profile metadata

### default

| Field    | Value           |
| -------- | --------------- |
| Assignee | `@theramagnoli` |
| Reviewer | _(omit)_        |
| Label    | _(omit)_        |

### cam

| Field    | Value              |
| -------- | ------------------ |
| Assignee | `@theramagnoli`    |
| Reviewer | `CAM-UANL`         |
| Label    | `ready-for-review` |

For cam only, before applying reviewer or label, verify they exist when possible:

- `gh label list`
- org and team lookup if `CAM-UANL` must be qualified as `ORG/CAM-UANL`

If reviewer or label is not available, skip it and tell the user what could not be applied. Still create the PR with everything that is available.

## Create command

Prefer GitHub CLI. Example after approval.

### default profile

```bash
git push -u origin HEAD

gh pr create \
  --base main \
  --title "Se agrega búsqueda de usuarios en administración" \
  --body "$(cat <<'EOF'
<exact body text approved at the gate>
EOF
)" \
  --assignee theramagnoli
```

### cam profile

```bash
git push -u origin HEAD

gh pr create \
  --base main \
  --title "Se agrega búsqueda de usuarios en administración" \
  --body "$(cat <<'EOF'
<exact body text approved at the gate>
EOF
)" \
  --assignee theramagnoli \
  --reviewer CAM-UANL \
  --label ready-for-review
```

Adjust `--base` to the repo default. If `--reviewer CAM-UANL` fails because it is a team, try the org and team form (for example `ORG/CAM-UANL`).

## Approval gate (required)

Never push or run `gh pr create` until the user approves the plan.

When asking for approval, show the PR plan as a rendered markdown table with exactly these rows, in this order, followed by the exact title and body text and a diff breakdown by area, then ask for approval in plain message text:

| Field    | Value                                                   |
| -------- | ------------------------------------------------------- |
| Profile  | `default` or `cam`                                      |
| Branch   | current branch name, plus whether it needs to be pushed |
| Base     | base branch name                                        |
| Title    | full Spanish title draft                                |
| Summary  | 2-4 simple sentences describing the outcome             |
| Changes  | bullets for each concrete change, separated with `<br>` |
| Assignee | assignee for the selected profile                       |
| Reviewer | reviewer for the selected profile, or _(none)_          |
| Label    | label for the selected profile, or _(none)_             |

Example plan format:

| Field    | Value                                                                                                                                                                                      |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Profile  | default                                                                                                                                                                                    |
| Branch   | feature/user-search                                                                                                                                                                        |
| Base     | main                                                                                                                                                                                       |
| Title    | Se agrega búsqueda de usuarios en administración                                                                                                                                           |
| Summary  | Este PR agrega la búsqueda de usuarios en administración para localizar cuentas más rápido. Ahora se puede buscar por nombre y matrícula y la tabla muestra las coincidencias encontradas. |
| Changes  | - Se agrega búsqueda de usuarios por nombre y matrícula<br>- Se normaliza el texto de búsqueda con unaccent<br>- Se actualiza la tabla de resultados para mostrar coincidencias            |
| Assignee | @theramagnoli                                                                                                                                                                              |
| Reviewer | _(none)_                                                                                                                                                                                   |
| Label    | _(none)_                                                                                                                                                                                   |

### Diff breakdown

Alongside the plan, show what kind of change this is by grouping the branch diff against the base. Use `git diff --numstat <base>...HEAD` and bucket the paths:

| Area                     | + / -    |
| ------------------------ | -------- |
| Backend (business logic) | +120 -30 |
| Views (frontend pages)   | +40 -5   |
| Tests                    | +60 -0   |
| Config                   | +3 -1    |
| Total                    | +223 -36 |

Adapt the path prefixes to the repo layout (`app/` or `src/` for backend, `resources/views` or `pages/` for views, `tests/` or `*.test.*` for tests, `config/` or `*.config.*` for config). Omit areas with no changes.

Always show the full overview (plan table plus exact title, body, and diff breakdown) before asking. Never ask for approval on a PR the user hasn't seen in full, and never use interactive question prompts, option pickers, or approval dialogs: ask in the same message, in plain text, and let the user reply or edit any field in chat.

## Draft-only requests

If the user only wants the PR title and description, return only those in the final format without creating the PR: Spanish title, then prose overview of 2-4 simple Spanish sentences, then a blank line, then a flat bullet list.

Example:

```text
Se corrige validación de fechas en reservaciones de lockers

Las reservaciones de lockers aceptaban fechas inválidas y quedaban en un estado inconsistente. Ahora las fechas se validan antes de guardar y los registros muestran el estado correcto.

- Se corrige validación de fechas en reservaciones de lockers
- Se actualiza cálculo del estado de los registros de lockers
```

Do not push or create the PR on draft-only requests.

## Related skills

If commits are still needed before the PR, use the `commit` skill first so the branch history stays small and granular with Spanish `Se + verbo` messages.
