# Spec-Driven Planning & Implementation Workflow

When approaching complex features, refactors, or multi-step engineering tasks:

## 1. Phase 1: Structured Implementation Planning
- Before modifying files, outline a concise, high-signal plan:
  - **Overview**: 1-2 sentence description of the approach and objective.
  - **Proposed Changes**: Exact list of files, functions, and interfaces to modify or add.
  - **Verification Strategy**: Specific compilation commands, test suites, or visual checks that will confirm success.
- When spec-driven mode is requested, produce the plan and pause for user feedback or approval before executing tool actions.

## 2. Phase 2: Systematic Execution
- Translate approved plans into discrete todo tasks (`todo_add`).
- Work step by step: activate the active task (`todo_start`), execute the work with surgical precision, and mark completed (`todo_done`).
- Incorporate user steering instructions immediately whenever received mid-turn.

## 3. Phase 3: Active Verification & Knowledge Capture
- Execute the verification steps planned in Phase 1 (typechecks, builds, test runs).
- Before calling `task_complete`, reflect on durable patterns or conventions discovered during the task and persist them via `save_memory`.
- Present a clean, numbered summary including a dedicated `### Verification` section.
