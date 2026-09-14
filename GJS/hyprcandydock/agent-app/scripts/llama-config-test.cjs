const assert = require('node:assert/strict');
const { buildLlamaServerArgs } = require('../electron/llama-server-manager.cjs');

const args = buildLlamaServerArgs({
  path: '/tmp/test-model.gguf',
  id: 'Qwen2.5-Coder-0.5B-Instruct',
}, {
  context: 0,
  maxTokens: 1024,
  threads: 4,
  batchSize: 128,
  ubatchSize: 32,
  parallel: 1,
});

assert.ok(args.includes('--threads'));
assert.ok(args.includes('4'));
assert.ok(args.includes('--batch-size'));
assert.ok(args.includes('128'));
assert.ok(args.includes('--ubatch-size'));
assert.ok(args.includes('32'));
assert.ok(args.includes('--ctx-size'));
assert.ok(args.includes('4096'));
assert.ok(args.includes('--n-predict'));
assert.ok(args.includes('1024'));

console.log('llama config profile ok');
