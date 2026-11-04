---
name: commit
description: Trigger when the user asks to commit, stage work, or draft a commit message.
---

# Commit

Create commits for the current changes following these conventions.

## When to use

Use this skill when the user asks to commit changes, stage work, or draft a commit message.

## Process

1. Inspect the working tree with `git --no-optional-locks status` and `git --no-pager diff` (plus `git --no-pager diff --staged` if needed).
2. Group changes into small, granular commits. Separate independent changes; never bundle unrelated work.
3. If more than one granular commit is planned, create them one by one without presenting the plan first. For a single commit, just create it (or return only the message in draft-only mode).

4. Stage only the files that belong to the current commit.
5. Draft the commit message with the rules below from the actual diff.
6. Commit with a HEREDOC so multiline messages stay intact. Example:

```bash
git commit -m "$(cat <<'EOF'
Se agrega búsqueda de usuarios por nombre y matrícula

- Se normaliza el texto mediante unaccent
- Se conserva el ordenamiento por coincidencia
EOF
)"
```

7. Run `git --no-optional-locks status` after committing to confirm the result.
8. If there are more independent change groups left, repeat from step 4 for each commit.
9. Do not push unless the user explicitly asks.
10. When more than one commit was created, close with a rendered markdown overview table with one row per commit plus the total diff:

    | Commit    | Message        | Diff     |
    | --------- | -------------- | -------- |
    | `abc1234` | Se agrega ...  | +120 -30 |
    | `def5678` | Se corrige ... | +15 -8   |
    | **Total** |                | +135 -38 |

    Get per-commit numbers with `git show --shortstat <sha>` and the total with `git diff --shortstat` over the committed range. For a single commit, no table is needed.

## Commit message rules

Generate one commit message in Spanish from the staged changes.

First identify the main intent of the change. Do not just list files, functions, or modified lines. Explain what behavior, functionality, or structure was added, fixed, modified, or removed.

### Subject (required)

- Must start exactly with: `Se`
- Format: `Se` + third-person singular verb + concrete activity
- Preferred verbs: agrega, implementa, corrige, modifica, actualiza, elimina, refactoriza, ajusta, integra, reemplaza, configura
- Use present indicative; no infinitives or participles
- Describe the result or purpose, not only the technical action
- When several related changes exist, prioritize the most important functional change
- Recommended length: 40-90 characters
- No trailing period
- No prefixes like `feat:`, `fix:`, `refactor:`, or `chore:`
- Do not mention file names unless indispensable to understand the change
- Avoid generic subjects such as "Se realizan cambios", "Se corrigen errores" o "Se hacen ajustes"

### Body (optional)

Include a body only when at least one of these is true:

- There are two or more relevant changes that do not fit clearly in the subject
- An important technical decision must be explained
- The change affects different layers, modules, or behaviors
- There is a relevant consequence that is not obvious from the subject

Body rules:

- Separate subject and body with a blank line
- Use a hyphen list
- At most 4 bullets
- Each bullet must describe a concrete change or its purpose
- Do not repeat or rephrase the subject
- Do not list irrelevant changes, formatting-only edits, or minor internal details

### Writing criteria

- Common technical English terms are allowed (endpoint, middleware, snapshot, join, payload, hook, cache, etc.)
- Keep proper names of classes, methods, endpoints, tables, and technologies when needed
- Do not invent functionality, causes, or results that cannot be deduced from the diff
- If the change is mainly a fix, use `corrige` or `ajusta` and state the exact behavior fixed
- If the change only reorganizes code without behavior changes, use `refactoriza`
- If the change includes both feature work and refactoring, prioritize the feature in the subject; mention refactoring in the body only if relevant

### Correct examples

```text
Se corrige validación de fechas en reservaciones de lockers
```

```text
Se agrega búsqueda de usuarios por nombre y matrícula

- Se normaliza el texto mediante unaccent
- Se conserva el ordenamiento por coincidencia
```

### Incorrect examples

```text
Se realizan varios cambios
Se modifican archivos del controlador
Agregar validación de usuarios
fix: se corrige formulario
```

### Output when only drafting a message

If the user only asks for the message and not to commit, return only the final commit message.
Do not include explanations, headings, quotes, code fences, meta commentary, or the original diff.
