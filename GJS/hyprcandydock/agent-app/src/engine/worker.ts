import { WebWorkerMLCEngineHandler } from '@mlc-ai/web-llm';

// Hook Web Worker with MLC Engine Handler
const handler = new WebWorkerMLCEngineHandler();

self.onmessage = (msg: MessageEvent) => {
  handler.onmessage(msg);
};
