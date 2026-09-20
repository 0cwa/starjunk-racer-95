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
  if (!Array.isArray(loaded) || loaded.length !== 2) {
    throw new Error("Spritely browser module returned unexpected entrypoints");
  }

  const [dispatch, dispatchAsync] = loaded;
  if (!dispatch || typeof dispatch.call !== "function") {
    throw new Error("Spritely browser module did not return a callable bridge");
  }
  if (!dispatchAsync || typeof dispatchAsync.call_async !== "function") {
    throw new Error("Spritely browser module did not return an async bridge");
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

  async function callAsync(operation, ...args) {
    const reflectedValues = await dispatchAsync.call_async(operation, ...args);
    const reflector = dispatchAsync.reflector;
    if (!reflector || typeof reflector.car !== "function") {
      throw new Error("Hoot async bridge reflector is unavailable");
    }
    return reflector.car(reflectedValues);
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
    async joinRoom(roomReference, racerId) {
      if (
        typeof roomReference !== "string" ||
        !roomReference.startsWith("ocapn://") ||
        typeof racerId !== "string" ||
        racerId.length === 0 ||
        racerId.length > 96
      ) {
        throw new Error("invalid room join request");
      }
      if ((await callAsync("join-room", roomReference, racerId)) !== true) {
        throw new Error("Spritely room join was not acknowledged");
      }
      const storedReference = call("joined-room-reference");
      const storedRacerId = call("joined-racer-id");
      if (storedReference !== roomReference || storedRacerId !== racerId) {
        throw new Error("Spritely room join state did not round-trip");
      }
      return Object.freeze({
        state: "joined",
        roomReference,
        racerId,
      });
    },
    async becomeReady(carContentId, trackContentId) {
      if (!this.readyContentValid(carContentId, trackContentId)) {
        throw new Error("ready content ids are invalid");
      }
      return (await callAsync("ready", carContentId, trackContentId)) === true;
    },
  });
}

export async function installSpritelyGodotBridge(options = {}) {
  const raceBridge = await loadSpritelyRaceBridge(options);
  const godotBridge = Object.freeze({
    controlProtocol: raceBridge.controlProtocol,
    readyContentValid(carContentId, trackContentId) {
      return raceBridge.readyContentValid(carContentId, trackContentId);
    },
    async joinRoom(roomReference, racerId) {
      const joined = await raceBridge.joinRoom(roomReference, racerId);
      return joined.roomReference;
    },
    async becomeReady(carContentId, trackContentId) {
      return await raceBridge.becomeReady(carContentId, trackContentId);
    },
  });
  globalThis.StarjunkSpritely = godotBridge;
  return godotBridge;
}
