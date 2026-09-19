/// <reference types="vite/client" />

declare module '*.wasm?url' {
  const url: string;
  export default url;
}

declare module '@wllama/wllama/esm/wasm/wllama.wasm?url' {
  const url: string;
  export default url;
}
