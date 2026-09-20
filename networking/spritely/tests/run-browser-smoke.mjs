import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";

const rootArg = process.argv[2];
const chromium = process.argv[3] ?? process.env.CHROMIUM_BIN ?? "chromium";
if (!rootArg) {
  throw new Error("usage: run-browser-smoke.mjs <browser-root> [chromium]");
}

const root = path.resolve(rootArg);
const mimeTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".txt", "text/plain; charset=utf-8"],
  [".wasm", "application/wasm"],
]);

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", "http://127.0.0.1/");
    const requested = url.pathname === "/" ? "/browser-smoke.html" : url.pathname;
    const file = path.resolve(root, "." + decodeURIComponent(requested));
    if (file !== root && !file.startsWith(root + path.sep)) {
      response.writeHead(403);
      response.end("forbidden");
      return;
    }

    const body = await readFile(file);
    response.writeHead(200, {
      "content-type": mimeTypes.get(path.extname(file)) ?? "application/octet-stream",
      "cache-control": "no-store",
    });
    response.end(body);
  } catch (error) {
    response.writeHead(error?.code === "ENOENT" ? 404 : 500);
    response.end(String(error));
  }
});

await new Promise((resolve, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", resolve);
});

const address = server.address();
if (!address || typeof address === "string") {
  server.close();
  throw new Error("unable to determine browser smoke server port");
}

const url = `http://127.0.0.1:${address.port}/browser-smoke.html`;
const args = [
  "--headless=new",
  "--no-sandbox",
  "--disable-dev-shm-usage",
  "--disable-gpu",
  "--virtual-time-budget=20000",
  "--dump-dom",
  url,
];

const child = spawn(chromium, args, {
  stdio: ["ignore", "pipe", "pipe"],
});

let stdout = "";
let stderr = "";
child.stdout.setEncoding("utf8");
child.stderr.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  stdout += chunk;
});
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

const timeout = setTimeout(() => {
  child.kill("SIGKILL");
}, 40000);

const exitCode = await new Promise((resolve, reject) => {
  child.once("error", reject);
  child.once("exit", (code, signal) => {
    if (signal) {
      reject(new Error(`Chromium terminated by ${signal}`));
      return;
    }
    resolve(code);
  });
}).finally(() => {
  clearTimeout(timeout);
  server.close();
});

if (exitCode !== 0 || !stdout.includes('data-status="passed"')) {
  process.stderr.write(stderr);
  process.stderr.write(stdout);
  throw new Error(
    `real-browser Spritely smoke failed (Chromium exit ${exitCode})`,
  );
}

console.log("Spritely browser remote room/readiness passed");
