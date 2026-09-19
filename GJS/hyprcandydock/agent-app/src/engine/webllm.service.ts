// Native llama.cpp is the only supported local inference backend.
// This compatibility adapter keeps the legacy AgentEngine API intact without
// importing Wllama/WebGPU code into the launcher bundle.
export type WebLLMInitProgress = {
  text: string;
  progress: number;
  error?: string;
};

type HardwareInfo = {
  supported: boolean;
  f16: boolean;
  adapterName?: string;
  error?: string;
};

class DisabledWebLLMService {
  private progress: WebLLMInitProgress = {
    text: 'WebLLM disabled; use native llama.cpp',
    progress: 0,
  };

  onProgress(listener: (report: WebLLMInitProgress) => void): () => void {
    listener(this.progress);
    return () => undefined;
  }

  setCustomModels(_models: unknown[]): void {}

  getHardwareInfo(): HardwareInfo {
    return {
      supported: false,
      f16: false,
      adapterName: 'native-llama.cpp',
      error: 'WebLLM/WebGPU inference is disabled; native llama.cpp is active.',
    };
  }

  isReady(_modelId?: string): boolean { return false; }
  isModelCached(_modelId: string): Promise<boolean> { return Promise.resolve(false); }
  listCachedModelIds(_modelIds: string[]): Promise<string[]> { return Promise.resolve([]); }
  getLoadedModel(): string | null { return null; }
  getEngine(): null { return null; }

  async ensureEngine(_modelId: string): Promise<never> {
    throw new Error('WebLLM is disabled; use the explicit native llama-server toggle.');
  }

  cancelLoading(): void {}
  interrupt(): void {}
  async unload(): Promise<void> {}
  async deleteModelCache(_modelId: string): Promise<void> {}
}

export const webllmService = new DisabledWebLLMService();
