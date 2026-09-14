#!/usr/bin/env node
const { LlamaServerManager } = require('../electron/llama-server-manager.cjs');
const modelId = process.argv[2] || 'Qwen2.5-Coder-1.5B-Instruct';
const manager = new LlamaServerManager();
manager.pull(modelId, (progress) => {
  const mb = (n) => n ? `${Math.round(n / 1024 / 1024)} MB` : '?';
  process.stdout.write(`\r${progress.text || 'Downloading…'} (${mb(progress.loaded)}/${mb(progress.total)})`);
}).then((model) => {
  process.stdout.write(`\nModel ready: ${model.id}\n${model.path}\n`);
}).catch((error) => { console.error(`\nModel pull failed: ${error.message}`); process.exitCode = 1; });
