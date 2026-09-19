const ED25519 = { name: "Ed25519" };

function asUint8Array(value) {
  return value instanceof Uint8Array ? value : new Uint8Array(value);
}

export function createGoblinsBrowserImports({
  cryptoApi = globalThis.crypto,
  WebSocketClass = globalThis.WebSocket,
} = {}) {
  if (!cryptoApi?.subtle || typeof cryptoApi.getRandomValues !== "function") {
    throw new Error("WebCrypto with SubtleCrypto is required");
  }
  if (typeof WebSocketClass !== "function") {
    throw new Error("WebSocket is required");
  }

  const subtle = cryptoApi.subtle;
  return {
    crypto: {
      async digest(algorithm, data) {
        return asUint8Array(await subtle.digest(algorithm, data));
      },
      randomValues(length) {
        const bytes = new Uint8Array(length);
        cryptoApi.getRandomValues(bytes);
        return bytes;
      },
      generateEd25519KeyPair() {
        return subtle.generateKey(ED25519, true, ["sign", "verify"]);
      },
      keyPairPrivateKey(keyPair) {
        return keyPair.privateKey;
      },
      keyPairPublicKey(keyPair) {
        return keyPair.publicKey;
      },
      async exportKey(key) {
        return asUint8Array(await subtle.exportKey("raw", key));
      },
      importPublicKey(key) {
        return subtle.importKey("raw", key, ED25519, true, ["verify"]);
      },
      async signEd25519(data, key) {
        return asUint8Array(
          await subtle.sign(ED25519, key?.privateKey ?? key, data),
        );
      },
      verifyEd25519(signature, data, publicKey) {
        return subtle.verify(ED25519, publicKey, signature, data);
      },
    },
    uint8Array: {
      new(length) {
        return new Uint8Array(length);
      },
      fromArrayBuffer(buffer) {
        return new Uint8Array(buffer);
      },
      length(array) {
        return array.length;
      },
      ref(array, index) {
        return array[index];
      },
      set(array, index, value) {
        array[index] = value;
      },
    },
    webSocket: {
      new(url) {
        const socket = new WebSocketClass(url);
        socket.binaryType = "arraybuffer";
        return socket;
      },
      close(socket) {
        socket.close();
      },
      send(socket, data) {
        socket.send(data);
      },
      setOnOpen(socket, callback) {
        socket.onopen = () => callback();
      },
      setOnError(socket, callback) {
        socket.onerror = () => callback();
      },
      setOnMessage(socket, callback) {
        socket.onmessage = (event) => callback(event.data);
      },
      setOnClose(socket, callback) {
        socket.onclose = (event) => callback(event.code, event.reason);
      },
    },
  };
}
