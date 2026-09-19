import assert from "node:assert/strict";
import fs from "node:fs";

import { createGoblinsBrowserImports } from "../browser-host.mjs";

const importsPath = process.argv[2];
if (!importsPath) {
  throw new Error("usage: browser-host-contract.mjs <wasm-imports.json>");
}

class FakeWebSocket {
  constructor(url) {
    this.url = url;
    this.binaryType = "";
    this.sent = [];
    this.closed = false;
    this.onopen = null;
    this.onerror = null;
    this.onmessage = null;
    this.onclose = null;
  }

  send(data) {
    this.sent.push(data);
  }

  close() {
    this.closed = true;
  }
}

const host = createGoblinsBrowserImports({ WebSocketClass: FakeWebSocket });
const wasmImports = JSON.parse(fs.readFileSync(importsPath, "utf8"));
const hootModules = new Set(["rt", "ffi", "debug", "io", "finalization"]);
const requiredHostImports = new Map();

for (const entry of wasmImports) {
  if (hootModules.has(entry.module)) {
    continue;
  }
  if (entry.kind !== "function") {
    throw new Error(
      `unsupported non-function browser import ${entry.module}.${entry.name}`,
    );
  }
  if (!requiredHostImports.has(entry.module)) {
    requiredHostImports.set(entry.module, new Set());
  }
  requiredHostImports.get(entry.module).add(entry.name);
}

assert.deepEqual(
  [...requiredHostImports.keys()].sort(),
  Object.keys(host).sort(),
  "browser host modules must exactly match non-Hoot Wasm imports",
);

for (const [moduleName, requiredNames] of requiredHostImports) {
  assert.deepEqual(
    [...requiredNames].sort(),
    Object.keys(host[moduleName]).sort(),
    `${moduleName} functions must exactly match compiled Wasm imports`,
  );
  for (const name of requiredNames) {
    assert.equal(typeof host[moduleName][name], "function");
  }
}

const bytes = host.uint8Array.new(3);
host.uint8Array.set(bytes, 1, 95);
assert.equal(host.uint8Array.length(bytes), 3);
assert.equal(host.uint8Array.ref(bytes, 1), 95);
assert.deepEqual(
  [...host.uint8Array.fromArrayBuffer(Uint8Array.from([1, 2, 3]).buffer)],
  [1, 2, 3],
);

const random = host.crypto.randomValues(32);
assert.equal(random.length, 32);
const digest = await host.crypto.digest("SHA-256", Uint8Array.from([9, 5]));
assert.equal(digest.length, 32);

const keyPair = await host.crypto.generateEd25519KeyPair();
const privateKey = host.crypto.keyPairPrivateKey(keyPair);
const publicKey = host.crypto.keyPairPublicKey(keyPair);
const exportedPublicKey = await host.crypto.exportKey(publicKey);
assert.equal(exportedPublicKey.length, 32);
const importedPublicKey = await host.crypto.importPublicKey(exportedPublicKey);
const payload = Uint8Array.from([1, 9, 9, 5]);
const signature = await host.crypto.signEd25519(payload, privateKey);
assert.equal(signature.length, 64);
assert.equal(
  await host.crypto.verifyEd25519(signature, payload, importedPublicKey),
  true,
);

const socket = host.webSocket.new("wss://example.invalid/room");
assert.equal(socket.binaryType, "arraybuffer");
host.webSocket.send(socket, Uint8Array.from([7]));
assert.equal(socket.sent.length, 1);

let opened = false;
host.webSocket.setOnOpen(socket, () => {
  opened = true;
});
socket.onopen({});
assert.equal(opened, true);

let message = null;
host.webSocket.setOnMessage(socket, (data) => {
  message = data;
});
const messageBuffer = Uint8Array.from([4, 2]).buffer;
socket.onmessage({ data: messageBuffer });
assert.equal(message, messageBuffer);

let closeInfo = null;
host.webSocket.setOnClose(socket, (code, reason) => {
  closeInfo = [code, reason];
});
socket.onclose({ code: 1000, reason: "done" });
assert.deepEqual(closeInfo, [1000, "done"]);

let errored = false;
host.webSocket.setOnError(socket, () => {
  errored = true;
});
socket.onerror(new Error("test"));
assert.equal(errored, true);

host.webSocket.close(socket);
assert.equal(socket.closed, true);

console.log("Spritely browser host contract passed");
