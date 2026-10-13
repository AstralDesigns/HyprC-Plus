#!/usr/bin/env python3
"""Standalone probe: does Qt WebEngine expose a usable WebGPU adapter?

Mirrors how bar/shell.qml hosts the agent (QtQuick WebEngineView via PyQt)
but with JS console bridged to stdout, so we can see exactly what
navigator.gpu.requestAdapter() resolves to under the real Chromium flags.

Run:  python3 webgpu_probe.py  (QTWEBENGINE_CHROMIUM_FLAGS from env or argv[1])
"""
import os
import sys

# Default to the SAME flag set as shell.qml's pragma Env
DEFAULT_FLAGS = (
    "--enable-gpu-rasterization --ignore-gpu-blocklist --enable-unsafe-webgpu "
    "--disable-background-timer-throttling --no-pings"
)
if len(sys.argv) > 1:
    os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = sys.argv[1]
elif "QTWEBENGINE_CHROMIUM_FLAGS" not in os.environ:
    os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = DEFAULT_FLAGS

from PyQt6.QtCore import QUrl, QTimer
from PyQt6.QtGui import QColor
from PyQt6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile
from PyQt6.QtWidgets import QApplication

HTML = """
<!doctype html><html><body><script>
(async () => {
  const say = (m) => console.log('PROBE| ' + m);
  try {
    say('navigator.gpu = ' + typeof navigator.gpu);
    if (!navigator.gpu) { say('RESULT: NO_GPU_OBJECT'); return; }
    say('isSecureContext = ' + isSecureContext + ', origin = ' + location.origin);
    const cands = [
      ['high-performance', { powerPreference: 'high-performance' }],
      ['low-power', { powerPreference: 'low-power' }],
      ['default', undefined],
      ['fallback', { forceFallbackAdapter: true }],
    ];
    let any = false;
    for (const [label, opt] of cands) {
      try {
        const a = opt ? await navigator.gpu.requestAdapter(opt) : await navigator.gpu.requestAdapter();
        if (a) {
          any = true;
          let info = a.info || {};
          if (!a.info && a.requestAdapterInfo) info = await a.requestAdapterInfo();
          say(label + ': OK vendor=' + info.vendor + ' arch=' + info.architecture +
              ' device=' + info.device + ' desc=' + info.description +
              ' fallback=' + a.isFallbackAdapter + ' f16=' + a.features.has('shader-f16') +
              ' limits.maxStorage=' + a.limits.maxStorageBufferBindingSize);
          try { const d = await a.requestDevice(); say(label + ': device OK -> ' + d.features.has('shader-f16')); d.destroy(); }
          catch (e) { say(label + ': requestDevice FAILED: ' + e); }
        } else {
          say(label + ': null');
        }
      } catch (e) { say(label + ': threw ' + e); }
    }
    say('RESULT: ' + (any ? 'ADAPTER_FOUND' : 'ALL_NULL'));
  } catch (e) { say('RESULT: FATAL ' + e); }
})();
</script></body></html>
"""


class Page(QWebEnginePage):
    def __init__(self, profile, parent=None):
        super().__init__(profile, parent)
        self._done = False

    def javaScriptConsoleMessage(self, level, message, line, source):
        print(message, flush=True)
        if "RESULT:" in message:
            self._done = True


app = QApplication(sys.argv)
profile = QWebEngineProfile("webgpu-probe", app)
page = Page(profile)
page.setHtml(HTML, QUrl("https://local.hycandy/webgpu-probe"))

# Fail-safe exit once the probe prints its RESULT line (or after 30s).
def tick():
    if page._done:
        app.quit()

t = QTimer(interval=300, timeout=tick)
t.start()
QTimer.singleShot(30000, app.quit)
app.exec()
