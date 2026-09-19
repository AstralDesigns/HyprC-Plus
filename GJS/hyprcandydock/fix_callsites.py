#!/usr/bin/env python3
"""Fix call sites: harden _setupAdBlocker invocations and add crash handlers."""

with open('app-launcher.js', 'r') as f:
    content = f.read()

# ============================================================
# FIX 1: _createTabWebView - harden adblock setup + crash handlers
# ============================================================
old_tab_call = """        const ucm = webView.get_user_content_manager();
        if (ucm && this._searxWebkitCacheDir) {
            this._setupAdBlocker(ucm, this._searxWebkitCacheDir);
        }

        const tab = {"""

new_tab_call = """        this._attachWebViewCrashHandlers(webView, 'tab-' + tabId);
        try {
            const ucm = (webView && typeof webView.get_user_content_manager === 'function')
                ? webView.get_user_content_manager()
                : null;
            if (ucm && this._searxWebkitCacheDir) {
                try {
                    this._setupAdBlocker(ucm, this._searxWebkitCacheDir);
                } catch (abErr) {
                    console.warn('[launcher] _createTabWebView adblock setup failed:', abErr.message);
                }
            }
        } catch (ucmErr) {
            console.warn('[launcher] _createTabWebView ucm setup error:', ucmErr.message);
        }

        const tab = {"""

assert old_tab_call in content, "FATAL: _createTabWebView call site pattern not found!"
content = content.replace(old_tab_call, new_tab_call, 1)
print('[OK] Fixed _createTabWebView adblock call site')

# ============================================================
# FIX 2: _buildAgentTab - add crash handlers to agent webView
# Inject crash handlers attachment after the UCM/logScript block ends (before workspace startup check)
# ============================================================
old_agent_ucm_end = """            } catch (e) {
                console.warn('[launcher] Failed to register agent script message handler:', e.message);
            }
        }

        if (!this._workspaceStartupEnabled) {"""

new_agent_ucm_end = """            } catch (e) {
                console.warn('[launcher] Failed to register agent script message handler:', e.message);
            }
        }

        this._attachWebViewCrashHandlers(webView, 'agent-ui');

        if (!this._workspaceStartupEnabled) {"""

assert old_agent_ucm_end in content, "FATAL: _buildAgentTab UCM block end pattern not found!"
content = content.replace(old_agent_ucm_end, new_agent_ucm_end, 1)
print('[OK] Fixed _buildAgentTab: added crash handlers')

with open('app-launcher.js', 'w') as f:
    f.write(content)

print('\\nAll call-site fixes applied.')
