# Project AI Instructions

## Project Context

This project is maintained across multiple development environments:

- Office computer
- Home computer
- Remote SSH servers

Git repository is the single source of truth.

Do not assume local machine state is shared between environments.

The project may be modified from different computers at different times.

Always consider synchronization and compatibility with other development environments.

---

# AI Working Principles

The AI assistant should act as a long-term project collaborator.

Before making changes:

1. Understand the existing implementation.
2. Check dependencies and impact.
3. Avoid unnecessary changes.
4. Preserve existing design decisions.

Prefer understanding before modifying.

---

# CodeGraph Usage

This project uses CodeGraph as the primary code intelligence system.

Use CodeGraph first when analyzing:

- project architecture
- module relationships
- dependencies
- function call chains
- class relationships
- impact of changes
- refactoring scope
- unfamiliar code

Do not rely only on text search when structural understanding is required.

Examples:

Use CodeGraph for questions like:

- "Who calls this function?"
- "What modules depend on this?"
- "What will be affected if this changes?"
- "Explain this subsystem architecture."

---

# CodeGraph Management

CodeGraph represents the current state of the codebase.

CodeGraph contains:

- project structure
- files
- symbols
- functions/classes
- dependencies
- callers/callees
- impact relationships

## Local Index Rules

The `.codegraph/` directory is a local generated index.

Rules:

- Never commit `.codegraph/` to Git.
- Each computer maintains its own CodeGraph index.
- The index can always be regenerated.
- Do not depend on another machine's `.codegraph/` data.

The project Git repository contains source and knowledge, not CodeGraph cache.

---

# CodeGraph Synchronization

After pulling code changes from Git:

Run:

```bash
codegraph sync
```

---

# Knowledge and Change Records

## Required Reading Order

Before changing the project, read `AGENTS.md`, `AI_CONTEXT.md`, `docs/README.md`, the task's Active document, and then the relevant source and call paths through CodeGraph. Read Historical records only when an earlier decision's reason is needed.

`AI_CONTEXT.md` is a concise snapshot of current project facts, not a chronological log. `docs/README.md` is the canonical documentation index and must be updated when a document is added, moved, superseded, or changes responsibility.

## CodeGraph and Markdown Responsibilities

- Source code plus CodeGraph are authoritative for current locations, symbols, dependencies, callers, and impact.
- Active Markdown documents are authoritative for current product contracts, platform setup, manual procedures, architecture decisions, and operational expectations.
- Historical records explain what happened at a point in time; they are not current requirements.
- When sources conflict, verify the current implementation first and repair the stale Active document.

After pulling changes, run `codegraph sync .`. After meaningful source changes, run `codegraph sync .` followed by `codegraph status .`. Run `codegraph index .` only when the index is missing or damaged, the extractor changed, or the tool recommends it.

## Local Operation and Update Records

Record each substantial task in `docs/history/YYYY-MM/YYYY-MM-DD-topic.md` using `docs/history/README.md`. Include scope, environment, branch and starting revision, affected files or modules, external operations, decisions, actual verification, remaining work, and rollback notes when applicable.

Create a record for architecture, API/DP contract, platform bridge, security, signing, deployment, migration, or cross-project changes. A trivial typo or formatting-only edit does not need a record. Freeze completed records and feed durable conclusions back into the relevant Active document.

Never record secrets, tokens, AppSecret values, passwords, signing material, private user or Wi-Fi data, full environment files, or local CodeGraph cache contents.

## Cross-Environment Handoff

Git remains the only shared source of truth across computers. A handoff must identify the branch, base revision, validation actually performed, unfinished work, and intentional local-only state. Do not depend on uncommitted files, editor state, SDK caches, build output, or another machine's `.codegraph/` directory.
