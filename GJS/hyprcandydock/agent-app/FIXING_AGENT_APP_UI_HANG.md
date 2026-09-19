# Fixing the GJS Launcher UI Hang Issue

## Problem Summary

The HyprCandy agent launcher UI occasionally hangs when the agent workspace is active. The issue occurs within the GJS (GNOME JavaScript) application, specifically when the embedded Electron agent renderer is running.

## Root Cause Analysis

After thorough examination of the codebase (`/home/king/.hyprcandy/GJS/hyprcandydock/agent-app`), the following factors contribute to the UI hang:

### 1. Improper Cleanup of Electron Processes

The `LlamaServerManager` class in `electron/llama-server-manager.cjs` manages the llama.cpp server process but may not properly terminate child processes on shutdown or error conditions.

**Issue:** The `stop()` method attempts to kill the child process but relies on `SIGKILL` and `SIGTERM`. If the process doesn't respond correctly, the Electron main process may remain blocked waiting for IPC communication channels.

**Evidence:**
- `electron/main.cjs` sets up the Electron process with various GPU-related flags
- `electron/llama-server-manager.cjs` creates the child process via `spawn()`
- The `stop()` method uses `child.kill('SIGKILL')` and `child.kill('SIGTERM')` but lacks robust error handling

### 2. IPC Communication Blocking

The bridge between GJS and Electron uses JSON-Line (NDJSON) protocol for communication. When the agent workspace is active, there may be:

- Unresolved promises in the `waitHealthy()` method
- Stalled IPC channels that prevent the GJS main thread from processing events
- Race conditions between the Electron worker and the GJS main process

**Evidence:**
- `bridge.ts` implements `postMessage` handlers that forward messages to the Electron process
- `electron/llama-server-manager.cjs` sends progress updates via `llama_progress` messages
- The `AgentBridge` class tracks pending requests but may leave orphaned promises

### 3. Resource Leaks in Model Management

The `AppState` global state and `store.ts` manage model loading and caching. Improper cleanup of model references can lead to memory exhaustion and unresponsive UI.

**Evidence:**
- `store.ts` maintains `activeModelState` checks that may not release resources promptly
- `preset models` are loaded eagerly even when not actively used
- The `activeModel` field persists across sessions

### 4. GPU/WebGPU Configuration Conflicts

While the Intel IGPU and AMD DGPU are functioning correctly, the hybrid rendering approach (Electron with WebGPU vs WebKitGTK) introduces complexity:

- Different GPU drivers may behave differently under heavy load
- The `disable-gpu` and related flags in `electron/main.cjs` may not be sufficient to prevent GPU hangs
- The `HYPRCANDY_LLAMA_GPU_LAYERS` environment variable affects whether GPU layers are used

## Recommended Solutions

### Solution 1: Robust Process Termination

**File:** `electron/llama-server-manager.cjs`

**Changes:**
1. Add a timeout-based termination mechanism for the child process
2. Implement graceful shutdown sequence before killing the process
3. Ensure all promise chains are resolved before process death

```typescript
// In LlamaServerManager class, modify the stop() method
async stop() {
  const child = this.child;
  
  // Wait for graceful shutdown with timeout
  const timeout = 30_000; // 30 seconds
  const startTime = Date.now();
  
  while (child && (Date.now() - startTime) < timeout) {
    try {
      await new Promise((resolve) => {
        child.once('exit', () => resolve());
      });
    } catch (err) {
      // Child died unexpectedly - proceed to force kill
      console.warn('LlamaServerManager child died unexpectedly:', err);
    }
  }
  
  // Force kill if still running
  if (child) {
    try {
      child.kill('SIGKILL');
      console.log('Force killed llama server process');
    } catch (e) {
      console.error('Failed to kill llama server:', e);
    }
  }
}
```

### Solution 2: IPC Channel Health Monitoring

**File:** `bridge.ts`

**Changes:**
1. Add heartbeat monitoring for IPC channels
2. Implement automatic recovery when channels stall
3. Log stalled channel events for debugging

```typescript
// In AgentBridge class, add a heartbeat monitor
private _heartbeatInterval: number = 0;
private _lastHeartbeat: number = 0;
private _stalledChannels: Set<string> = new Set();

constructor() {
  // ... existing init code ...
  this._heartbeatInterval = 5000; // Check every 5 seconds
}

// Start heartbeat monitoring
startHeartbeatMonitoring() {
  this._heartbeatInterval = setInterval(() => {
    const now = Date.now();
    this._lastHeartbeat = now;
    
    // Check for stalled IPC channels
    const stalled = this._stalledChannels.size > 0;
    if (stalled) {
      this._stalledChannels.forEach(id => {
        console.warn(`Stalled IPC channel ${id} detected`);
        // Trigger recovery mechanism
        this.recoverStalledChannel(id);
      });
    }
  }, this._heartbeatInterval);
}

recoverStalledChannel(channelId: string) {
  // Send recovery signal to the channel
  this.handleIncoming({
    type: 'recovery_request',
    channelId,
    payload: { action: 'recover' }
  });
}
```

### Solution 3: Model State Cleanup

**File:** `src/App.tsx` and `src/store.ts`

**Changes:**
1. Clear unused model references periodically
2. Implement proper cleanup on session close
3. Use weak references for model caches

```typescript
// In App.tsx, wrap the useEffect cleanup
import { useEffect, useCleanup } from 'react';

useEffect(() => {
  // ... existing setup code ...
  
  // Cleanup function
  useCleanup(() => {
    // Clear active model state
    storeActions.clearModel();
    
    // Stop any running llama-server
    if (this.llamaServer) {
      this.llamaServer.stop();
    }
    
    // Clear store state
    store.dispatch({ type: 'reset_model_state' });
  });
}, []);
```

### Solution 4: Environment Variable Sanitization

**File:** `electron/main.cjs`

**Changes:**
1. Validate GPU-related environment variables
2. Ensure consistent GPU configuration across modes

```javascript
// In electron/main.cjs, add validation
const VALID_GPU_VARIABLES = [
  'HYPRCANDY_LLAMA_GPU_LAYERS',
  'HYPRCANDY_LLAMA_GPU_LAYERS',
];

if (process.env.HYPRCANDY_LLAMA_GPU_LAYERS) {
  const val = process.env.HYPRCANDY_LLAMA_GPU_LAYERS;
  if (!VALID_GPU_VARIABLES.includes(val)) {
    console.warn('Invalid HYPRCANDY_LLAMA_GPU_LAYERS value:', val);
    delete process.env.HYPRCANDY_LLAMA_GPU_LAYERS;
  }
}
```

## Implementation Priority

1. **Critical:** Fix `LlamaServerManager.stop()` for proper process termination
2. **High:** Add IPC heartbeat monitoring in `AgentBridge`
3. **Medium:** Improve model state cleanup in `App.tsx` and `store.ts`
4. **Low:** Validate GPU environment variables in `electron/main.cjs`

## Testing Strategy

1. **Unit Tests:** Verify process termination works correctly under various failure scenarios
2. **Integration Tests:** Simulate agent workspace activation and verify UI responsiveness
3. **Load Testing:** Run multiple concurrent agent sessions to ensure stability
4. **Edge Cases:** Test with GPU disabled, network partitions, and resource exhaustion

## Expected Outcome

After implementing these changes, the GJS launcher UI should:
- No longer hang when the agent workspace is active
- Properly recover from stalled IPC channels
- Cleanly shut down Electron processes without leaving zombie processes
- Maintain responsive UI even under heavy load

## References

- `electron/llama-server-manager.cjs` - Manages llama.cpp server lifecycle
- `electron/main.cjs` - Sets up Electron process with GPU configurations
- `bridge.ts` - Handles IPC between GJS and Electron
- `App.tsx` - Main React application component
- `store.ts` - Global state management for the agent app
