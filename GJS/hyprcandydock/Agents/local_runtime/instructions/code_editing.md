# Codebase Precision & Engineering Discipline

This guide outlines core principles for editing codebases with zero regressions and maximum architectural precision.

## 1. Grounded Context Gathering (Inspect Before You Touch)
- Never assume an API, type signature, or file structure exists without verifying.
- Call `read_file` to inspect the full surrounding context, imports, existing patterns, and exported types before proposing edits.
- Map the dependencies: identify callers, callees, and any state or event listeners connected to the target code.
- Observe existing formatting conventions (indentation style, single vs double quotes, trailing commas, naming conventions) and adhere to them strictly.

## 2. Minimal Surgical Diffs
- Make the smallest possible change that cleanly and robustly achieves the objective.
- Never rewrite working helper functions or replace entire files when a surgical edit to a few lines or branches suffices.
- Preserve all existing comments, docstrings, type annotations, and error boundaries unless explicitly requested to change them.
- Avoid introducing unnecessary external dependencies or side effects.

## 3. Idiomatic Patterns & Design Integrity
- Respect the idioms of the host project:
  - If a project uses dynamic theme tokens or CSS variables, use them instead of hardcoding raw values.
  - If a project uses a specific state management pattern (stores, signals, hooks, context), follow that pattern consistently.
  - Keep types strictly typed: avoid escaping to `any` unless bridging untyped third-party boundaries.

## 4. Empirical Verification Before Completion
- Never claim a task is complete based on hope or assumption.
- Run static type checks (`tsc --noEmit`), syntax compilation (`py_compile`, `bash -n`), and test suites before calling `task_complete`.
- If visual UI elements were modified, trigger the view and verify layout, contrast, and responsiveness.
