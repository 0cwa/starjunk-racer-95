import { createGoblinsBrowserImports } from "./browser-host.mjs";
import { installSpritelyGodotBridge } from "./browser-race-bridge.mjs";

const status = document.getElementById("status");
const validCar = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const validTrack = "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
const racerId = "chromium-racer-95";

function mark(state, text) {
  document.body.dataset.status = state;
  status.textContent = text;
}

try {
  mark("loading-reference", "loading room reference");
  const roomReference = (await (await fetch("./room-reference.txt")).text()).trim();
  if (!roomReference.startsWith("ocapn://")) {
    throw new Error("browser smoke room reference is invalid");
  }

  mark("loading-bridge", "loading Hoot race bridge");
  const bridge = await installSpritelyGodotBridge({
    SchemeClass: globalThis.HootScheme,
    userImports: createGoblinsBrowserImports(),
  });

  if (bridge.controlProtocol !== "starjunk95/race-control/3") {
    throw new Error(`unexpected control protocol: ${bridge.controlProtocol}`);
  }
  if (globalThis.StarjunkSpritely !== bridge) {
    throw new Error("Godot-visible Spritely bridge was not installed globally");
  }
  if (!bridge.readyContentValid(validCar, validTrack)) {
    throw new Error("canonical ready content IDs were rejected");
  }
  if (bridge.readyContentValid("sha256:NOT-CANONICAL", validTrack)) {
    throw new Error("invalid ready content ID crossed the browser bridge");
  }

  mark("cancelling-join", "proving pending join cancellation releases authority");
  const cancelledJoin = bridge.joinRoom(roomReference, racerId + "-cancelled");
  if (!bridge.leaveRoom()) {
    throw new Error("pending browser room join could not be cancelled");
  }
  let cancelled = false;
  try {
    await cancelledJoin;
  } catch (error) {
    cancelled = String(error).includes("cancelled");
  }
  if (!cancelled) {
    throw new Error("cancelled browser room join unexpectedly completed");
  }

  mark("joining", "joining remote Spritely room");
  const joinedReference = await bridge.joinRoom(roomReference, racerId);
  if (joinedReference !== roomReference) {
    throw new Error("Godot-visible room join did not preserve sturdyref");
  }

  mark("readying", "binding racer readiness to content");
  if (!(await bridge.becomeReady(validCar, validTrack))) {
    throw new Error("browser racer readiness was not acknowledged");
  }

  mark("leaving", "releasing browser racer authority");
  if (!bridge.leaveRoom()) {
    throw new Error("Godot-visible browser bridge did not release room authority");
  }

  mark("passed", "Spritely browser join/readiness/leave passed");
  document.title = "Starjunk Spritely browser smoke passed";
} catch (error) {
  mark("failed", error?.stack ?? String(error));
  document.title = "Starjunk Spritely browser smoke failed";
  console.error(error);
}
