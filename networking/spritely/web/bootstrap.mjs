import { createGoblinsBrowserImports } from "./browser-host.mjs";
import { installSpritelyGodotBridge } from "./browser-race-bridge.mjs";

const assetRoot = new URL("./", import.meta.url);
const reflectWasmDir = assetRoot.href.endsWith("/")
  ? assetRoot.href.slice(0, -1)
  : assetRoot.href;

async function bootSpritely() {
  if (!globalThis.HootScheme || typeof globalThis.HootScheme.load_main !== "function") {
    throw new Error("Hoot Scheme runtime was not loaded before Spritely bootstrap");
  }

  return await installSpritelyGodotBridge({
    SchemeClass: globalThis.HootScheme,
    wasmUrl: new URL("starjunk-spritely-room.wasm", assetRoot).href,
    reflectWasmDir,
    userImports: createGoblinsBrowserImports(),
  });
}

if (!globalThis.StarjunkSpritelyReady) {
  globalThis.StarjunkSpritelyReady = bootSpritely();
}

await globalThis.StarjunkSpritelyReady;
console.log("STARJUNK_SPRITELY_READY_JSON:" + JSON.stringify({ ready: true }));
