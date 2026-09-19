import { createGoblinsBrowserImports } from "./browser-host.mjs";

const status = document.getElementById("status");

try {
  if (!globalThis.HootScheme) {
    throw new Error("Hoot Scheme runtime did not initialize");
  }

  await globalThis.HootScheme.load_main("./starjunk-spritely-room.wasm", {
    reflect_wasm_dir: ".",
    user_imports: createGoblinsBrowserImports(),
  });

  document.body.dataset.status = "passed";
  status.textContent = "Spritely browser Wasm instantiated";
  document.title = "Starjunk Spritely browser smoke passed";
} catch (error) {
  document.body.dataset.status = "failed";
  status.textContent = error?.stack ?? String(error);
  document.title = "Starjunk Spritely browser smoke failed";
  console.error(error);
}
