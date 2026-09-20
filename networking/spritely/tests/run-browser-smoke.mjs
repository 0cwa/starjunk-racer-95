import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";

const rootArg = process.argv[2];
const chromium = process.argv[3] ?? process.env.CHROMIUM_BIN ?? "chromium";
const chromeDriver = process.argv[4] ?? process.env.CHROMEDRIVER_BIN ?? "chromedriver";
const page = process.argv[5] ?? "browser-smoke.html";
if (!rootArg) {
  throw new Error(
    "usage: run-browser-smoke.mjs <browser-root> [chromium] [chromedriver] [page]",
  );
}
if (page.startsWith("/") || page.includes("..")) {
  throw new Error("browser smoke page must stay within the served root");
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
const pageUrl = `http://127.0.0.1:${address.port}/${page}`;

const driverPort = 9515;
const driverUrl = `http://127.0.0.1:${driverPort}`;
const driver = spawn(chromeDriver, [`--port=${driverPort}`, "--allowed-ips=127.0.0.1"], {
  stdio: ["ignore", "pipe", "pipe"],
});
let driverStdout = "";
let driverStderr = "";
driver.stdout.setEncoding("utf8");
driver.stderr.setEncoding("utf8");
driver.stdout.on("data", (chunk) => {
  driverStdout += chunk;
});
driver.stderr.on("data", (chunk) => {
  driverStderr += chunk;
});

async function webdriver(method, pathname, body) {
  const response = await fetch(driverUrl + pathname, {
    method,
    headers: body === undefined ? undefined : { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok || payload.value?.error) {
    throw new Error(
      `WebDriver ${method} ${pathname} failed: ${JSON.stringify(payload.value ?? payload)}`,
    );
  }
  return payload.value;
}

async function waitForDriver() {
  let lastError;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const response = await fetch(driverUrl + "/status");
      if (response.ok) {
        return;
      }
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw lastError ?? new Error("ChromeDriver did not become ready");
}

let sessionId = null;
try {
  await waitForDriver();
  const session = await webdriver("POST", "/session", {
    capabilities: {
      alwaysMatch: {
        browserName: "chrome",
        "goog:chromeOptions": {
          binary: chromium,
          args: [
            "--headless=new",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "--disable-gpu",
          ],
        },
      },
    },
  });
  sessionId = session.sessionId;
  await webdriver("POST", `/session/${sessionId}/url`, { url: pageUrl });

  let lastState = { status: "", text: "" };
  for (let attempt = 0; attempt < 300; attempt += 1) {
    lastState = await webdriver(
      "POST",
      `/session/${sessionId}/execute/sync`,
      {
        script:
          "return {status: document.body?.dataset?.status || '', text: document.getElementById('status')?.textContent || ''};",
        args: [],
      },
    );

    if (lastState.status === "passed") {
      console.log("Spritely browser remote room/readiness passed");
      break;
    }
    if (lastState.status === "failed") {
      throw new Error(`browser smoke failed: ${lastState.text}`);
    }
    if (attempt === 299) {
      throw new Error(
        `browser smoke timed out in state ${JSON.stringify(lastState)}`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
} catch (error) {
  process.stderr.write(driverStdout);
  process.stderr.write(driverStderr);
  throw error;
} finally {
  if (sessionId !== null) {
    try {
      await webdriver("DELETE", `/session/${sessionId}`);
    } catch {
      // The primary failure, if any, is more useful than cleanup noise.
    }
  }
  driver.kill("SIGTERM");
  server.close();
}
