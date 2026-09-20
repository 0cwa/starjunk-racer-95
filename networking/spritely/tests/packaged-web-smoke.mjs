const status = document.getElementById("status");
const validCar = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const validTrack = "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
const racerId = "packaged-racer-95";

function mark(state, text) {
  document.body.dataset.status = state;
  status.textContent = text;
}

async function waitForBridge() {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (globalThis.StarjunkSpritelyReady) {
      return await globalThis.StarjunkSpritelyReady;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Spritely bootstrap did not publish StarjunkSpritelyReady");
}

try {
  mark("loading-reference", "loading packaged room reference");
  const roomReference = (await (await fetch("./room-reference.txt")).text()).trim();
  if (!roomReference.startsWith("ocapn://")) {
    throw new Error("packaged room reference is invalid");
  }

  mark("loading-bridge", "waiting for packaged Spritely bootstrap");
  const bridge = await waitForBridge();
  if (globalThis.StarjunkSpritely !== bridge) {
    throw new Error("packaged bootstrap did not install Godot-visible bridge");
  }
  if (bridge.controlProtocol !== "starjunk95/race-control/3") {
    throw new Error(`unexpected packaged control protocol: ${bridge.controlProtocol}`);
  }

  mark("joining", "joining through packaged Spritely runtime");
  if ((await bridge.joinRoom(roomReference, racerId)) !== roomReference) {
    throw new Error("packaged join did not preserve sturdyref");
  }

  mark("readying", "binding packaged racer readiness");
  if (!(await bridge.becomeReady(validCar, validTrack))) {
    throw new Error("packaged readiness was not acknowledged");
  }

  mark("unreadying", "clearing packaged racer readiness");
  if (!(await bridge.becomeUnready())) {
    throw new Error("packaged unready was not acknowledged");
  }

  mark("leaving", "releasing packaged racer authority");
  if (!bridge.leaveRoom()) {
    throw new Error("packaged leave did not release authority");
  }

  mark("passed", "Packaged Spritely Web bootstrap passed");
  document.title = "Starjunk packaged Spritely smoke passed";
} catch (error) {
  mark("failed", error?.stack ?? String(error));
  document.title = "Starjunk packaged Spritely smoke failed";
  console.error(error);
}
