# Systematic Debugging & Root-Cause Diagnosis

When diagnosing unexpected behavior, race conditions, hangs, or state desynchronization:

## 1. Trace the Complete Data Flow
- Trace the lifecycle of data end-to-end:
  `Input / Event Trigger` -> `Event Dispatcher` -> `State Transformation` -> `IPC / Protocol / Network` -> `Host / OS Execution` -> `State Reflection & UI Render`.
- Identify the exact link where reality diverges from expectation. Do not guess; locate the divergence empirically.

## 2. Diagnose Asynchronous Race Conditions & Event Loops
- Look for multiple event handlers attached to the same trigger (e.g. duplicate keydown listeners on window and editor).
- Watch for feedback loops between writes and watchers (e.g. an application writing to disk, followed by an inotify watcher reporting the app's own write as an external change).
- When handling local writes, implement write suppression or sequence tokening to prevent self-triggering loops.

## 3. Verify Hypotheses with Isolated Probes
- Formulate a testable hypothesis before altering code.
- Test the hypothesis using targeted command-line tools (`curl`, `lsof`, process inspection, test runners).
- Check process stderr, system logs, and developer console outputs for silent errors or unhandled promise rejections.

## 4. Validate with Regression Checks
- Once a fix is implemented, reproduce the original condition to confirm the issue is resolved.
- Verify that adjacent flows and standard use cases continue functioning without regression.
