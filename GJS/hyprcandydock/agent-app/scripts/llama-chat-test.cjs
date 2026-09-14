#!/usr/bin/env node
const { LlamaServerManager } = require('../electron/llama-server-manager.cjs');
const modelId = process.argv[2] || 'Qwen2.5-Coder-1.5B-Instruct';
const prompt = process.argv.slice(3).join(' ') || 'Write a one-line Python function that adds two numbers. Reply with code only.';
const manager = new LlamaServerManager();

(async () => {
  await manager.start(modelId, { context: 2048, maxTokens: 128 }, (progress) => process.stderr.write(`\r${progress.text || ''}`));
  process.stderr.write(`\nllama-server ready: ${modelId}\n`);
  const response = await fetch('http://127.0.0.1:17843/v1/chat/completions', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: modelId, messages: [{ role: 'user', content: prompt }], temperature: 0.1, max_tokens: 128, stream: false }),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${await response.text()}`);
  const result = await response.json();
  const text = result?.choices?.[0]?.message?.content || '';
  if (!text.trim()) throw new Error(`No assistant content: ${JSON.stringify(result)}`);
  console.log(text.trim());
  console.error(`\nSmoke test passed; usage=${JSON.stringify(result.usage || {})}`);
})().catch((error) => { console.error(`Smoke test failed: ${error.stack || error}`); process.exitCode = 1; }).finally(() => manager.stop());
