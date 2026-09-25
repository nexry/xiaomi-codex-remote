#!/usr/bin/env node
import { fileURLToPath } from "node:url";
import { readFile } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { CodexMicroEmulator } from "../src/emulator.js";
import { Link } from "../src/link.js";
import { SocketTransport } from "../src/transports/socket.js";
import { SocketServerTransport } from "../src/transports/socket-server.js";
import { StreamDeckBackend } from "../src/streamdeck.js";
import { KeyboardInput } from "../src/keyboard-input.js";
import { XiaomiRemoteBackend } from "../src/xiaomi/backend.js";
import { StdinSource } from "../src/xiaomi/stdin.js";
import { BleSource } from "../src/xiaomi/ble.js";
import { IpcSource } from "../src/xiaomi/ipc.js";

const DEFAULT_SOCKET = path.join(os.tmpdir(), "codex-micro-vhid.sock");

export function parseArgs(argv) {
  const opts = {
    input: "xiaomi", mode: "shim", socket: process.env.CODEX_MICRO_SOCKET || DEFAULT_SOCKET,
    battery: 100, verbose: false, xiaomiSource: "stdin",
  };
  const values = { "--input": "input", "--mode": "mode", "--socket": "socket",
    "--battery": "battery", "--xiaomi-source": "xiaomiSource", "--xiaomi-config": "xiaomiConfig" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (Object.hasOwn(values, arg)) {
      const value = argv[++i];
      if (!value || value.startsWith("--")) throw new Error(`Missing value for ${arg}`);
      opts[values[arg]] = arg === "--battery" ? Number(value) : value;
    } else if (arg === "--verbose" || arg === "-v") opts.verbose = true;
    else if (arg === "--help" || arg === "-h") opts.help = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!["xiaomi", "keyboard", "streamdeck"].includes(opts.input)) throw new Error("Invalid --input; expected xiaomi|keyboard|streamdeck");
  if (!["helper", "shim"].includes(opts.mode)) throw new Error("Invalid --mode; expected helper|shim");
  const xiaomiSources = ["stdin", "ble", "ipc", "miremote", "sayall"];
  if (!xiaomiSources.includes(opts.xiaomiSource)) {
    throw new Error(`Invalid --xiaomi-source; expected ${xiaomiSources.join("|")}`);
  }
  if (!Number.isInteger(opts.battery) || opts.battery < 0 || opts.battery > 100) throw new Error("--battery must be an integer from 0 to 100");
  return opts;
}

function usage() {
  console.log(`xiaomi-codex-remote — Xiaomi RC003 → Codex Micro bridge (buttons MVP)

Usage: xiaomi-codex-remote [options]
  --input <xiaomi|keyboard|streamdeck>  Input backend (default: xiaomi)
  --mode <shim|helper>                 Host transport (default: shim)
  --xiaomi-source <stdin|ble|ipc|miremote|sayall> Default: stdin JSONL; miremote/ipc: normalized native events
  --xiaomi-config <path>               JSON mapping overrides (see config/)
  --battery <0-100>                    Reported battery (default: 100)
  -v, --verbose                       Log RPC requests and notifications
  -h, --help                          Show help

stdin: one {"key":"home","action":"press"} per line; release/repeat supported.
miremote/ipc: connects to native Xiaomi Codex Remote menu bar app with Bluetooth ATVV voice and MiCodexRemote loopback.
shim: listen for the existing node-hid shim. helper: connect to native helper.
See README.md for host compatibility limitations and launch instructions.`);
}

export async function main(argv = process.argv.slice(2)) {
  const opts = parseArgs(argv);
  if (opts.help) return usage();
  const emulator = new CodexMicroEmulator({ battery: opts.battery });
  if (opts.verbose) {
    emulator.on("request", ({ method, id }) => console.error(`[rpc] <- ${method} (id ${id})`));
    emulator.on("send", (line) => console.error(`[rpc] -> ${line.trim()}`));
    emulator.on("log", (level, ...args) => console.error(`[${level}]`, ...args));
    emulator.on("lighting", (model) => console.error("[lighting]", JSON.stringify(model)));
  }

  let input;
  if (opts.input === "xiaomi") {
    const mapping = opts.xiaomiConfig ? JSON.parse(await readFile(opts.xiaomiConfig, "utf8")) : {};
    const Source = {
      stdin: StdinSource,
      ble: BleSource,
      ipc: IpcSource,
      miremote: IpcSource,
      sayall: IpcSource,
    }[opts.xiaomiSource];
    input = new XiaomiRemoteBackend(emulator, { mapping, source: new Source() });
  } else if (opts.input === "keyboard") input = new KeyboardInput(emulator);
  else input = new StreamDeckBackend(emulator);

  const transport = opts.mode === "shim" ? new SocketServerTransport(opts.socket) : new SocketTransport(opts.socket);
  let link;
  let closing;
  let started = false;
  const shutdown = (code = 0) => {
    if (code) process.exitCode = code;
    if (closing) return closing;
    closing = (async () => {
      process.off("SIGINT", onSignal);
      process.off("SIGTERM", onSignal);
      try { await input.stop?.(); }
      finally {
        // CLI owns stdin; a paused pipe can otherwise keep the process alive.
        if (opts.input === "xiaomi" && opts.xiaomiSource === "stdin") process.stdin.destroy();
        // Allow release notifications queued during stop to reach the socket.
        await new Promise((resolve) => setImmediate(resolve));
        link?.dispose();
        transport.close();
      }
    })();
    return closing;
  };
  const fail = (error) => {
    console.error(error.message);
    void shutdown(1).catch((err) => console.error(err.message));
  };
  const onSignal = () => { void shutdown().catch(fail); };
  transport.on("error", (error) => { if (started) fail(error); });
  input.on?.("error", fail);
  input.on?.("end", onSignal);
  try {
    if (opts.mode === "shim") {
      await transport.listen();
      transport.on("open", () => console.error("Shim connected."));
      transport.on("client-close", () => {
        input.releaseAll?.();
        console.error("Shim disconnected (waiting for reconnect).");
      });
    } else await transport.connect();
    link = new Link(emulator, transport);
    process.on("SIGINT", onSignal);
    process.on("SIGTERM", onSignal);
    await input.start();
    started = true;
    if (!closing) {
      const audioStatus = ["miremote", "sayall", "ipc"].includes(opts.xiaomiSource) ? "audio routed via MiCodexRemote" : "audio not implemented";
      console.error(`${opts.input} input ready${opts.input === "xiaomi" ? ` (${opts.xiaomiSource}; ${audioStatus})` : ""}. ${opts.mode} socket: ${opts.socket}`);
    }
  } catch (error) {
    await shutdown(1);
    throw error;
  }
}

export function run() {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) run();
export { DEFAULT_SOCKET, fileURLToPath };
