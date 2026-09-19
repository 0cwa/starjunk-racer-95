import { createGoblinsBrowserImports } from "./browser-host.mjs";
import { loadSpritelyRaceBridge } from "./browser-race-bridge.mjs";

const status = document.getElementById("status");
const validCar = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const validTrack = "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";

try {
  const bridge = await loadSpritelyRaceBridge({
    SchemeClass: globalThis.HootScheme,
    userImports: createGoblinsBrowserImports(),
  });

  if (bridge.controlProtocol !== "starjunk95/race-control/3") {
    throw new Error(`unexpected control protocol: ${bridge.controlProtocol}`);
  }
  if (!bridge.browserCapnSupported) {
    throw new Error("browser CapTP bootstrap is not available");
  }
  if (!bridge.readyContentValid(validCar, validTrack)) {
    throw new Error("canonical ready content IDs were rejected");
  }
  if (bridge.readyContentValid("sha256:NOT-CANONICAL", validTrack)) {
    throw new Error("invalid ready content ID crossed the browser bridge");
  }

  document.body.dataset.status = "passed";
  status.textContent = "Spritely race-domain browser bridge passed";
  document.title = "Starjunk Spritely browser smoke passed";
} catch (error) {
  document.body.dataset.status = "failed";
  status.textContent = error?.stack ?? String(error);
  document.title = "Starjunk Spritely browser smoke failed";
  console.error(error);
}
