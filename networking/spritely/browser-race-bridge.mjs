export async function loadSpritelyRaceBridge({
  SchemeClass = globalThis.HootScheme,
  wasmUrl = "./starjunk-spritely-room.wasm",
  reflectWasmDir = ".",
  userImports,
} = {}) {
  if (!SchemeClass || typeof SchemeClass.load_main !== "function") {
    throw new Error("Hoot Scheme runtime is required");
  }
  if (!userImports || typeof userImports !== "object") {
    throw new Error("Spritely browser host imports are required");
  }

  const loaded = await SchemeClass.load_main(wasmUrl, {
    reflect_wasm_dir: reflectWasmDir,
    user_imports: userImports,
  });
  if (!Array.isArray(loaded) || loaded.length !== 1) {
    throw new Error("Spritely browser module returned an unexpected entrypoint");
  }

  const dispatch = loaded[0];
  if (!dispatch || typeof dispatch.call !== "function") {
    throw new Error("Spritely browser module did not return a callable bridge");
  }

  function call(operation, ...args) {
    const results = dispatch.call(operation, ...args);
    if (!Array.isArray(results) || results.length !== 1) {
      throw new Error(
        `Spritely bridge operation ${operation} returned ${results?.length ?? "invalid"} results`,
      );
    }
    return results[0];
  }

  const controlProtocol = call("control-protocol");
  const browserCapnSupported = call("browser-capn-supported");
  if (typeof controlProtocol !== "string" || typeof browserCapnSupported !== "boolean") {
    throw new Error("Spritely bridge bootstrap values have invalid types");
  }

  return Object.freeze({
    controlProtocol,
    browserCapnSupported,
    readyContentValid(carContentId, trackContentId) {
      if (typeof carContentId !== "string" || typeof trackContentId !== "string") {
        return false;
      }
      return call("ready-content-valid", carContentId, trackContentId) === true;
    },
  });
}
