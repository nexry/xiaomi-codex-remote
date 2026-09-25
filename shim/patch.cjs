// node-hid shim (CommonJS — loaded via NODE_OPTIONS="--require preload.cjs").
//
// Monkeypatches the `node-hid` module the ChatGPT app loads so it enumerates a
// synthetic Codex Micro and, when opened, returns a fake device whose 64-byte
// HID reports are forwarded over a Unix socket to the external bridge (the same
// SocketServerTransport / emulator / Stream Deck stack the native helper used).
//
// Self-contained: depends only on Node built-ins, so it can be injected into the
// app's main process without pulling in the ESM `src/` code.

const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const fs = require("node:fs");
const { EventEmitter } = require("node:events");

const REPORT_SIZE = 64;
const FAKE_PATH = "codex-micro-virtual";

// Descriptor the app's discovery must accept: VID 0x303A, PID 0x8360, vendor
// usage page 0xFF00, "Work Louder" manufacturer, USB (release low bits clear).
const FAKE_DESCRIPTOR = Object.freeze({
  vendorId: 0x303a,
  productId: 0x8360,
  path: FAKE_PATH,
  serialNumber: "codex-micro-emulator",
  manufacturer: "Work Louder",
  product: "Codex Micro",
  release: 0x0100,
  interface: 0,
  usagePage: 0xff00,
  usage: 0x01,
});

function defaultSocketPath() {
  return process.env.CODEX_MICRO_SOCKET || path.join(os.tmpdir(), "codex-micro-vhid.sock");
}

function log(msg) {
  const file = process.env.CODEX_MICRO_SHIM_LOG;
  if (!file) return;
  try {
    const prefix = `[${new Date().toISOString()} pid:${process.pid} ${process.type || "main"}]`;
    fs.appendFileSync(file, `${prefix} ${msg}\n`);
  } catch {
    /* logging is best-effort */
  }
}

/** Pad/truncate a Buffer to exactly one 64-byte report frame. */
function toFrame(data) {
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (buf.length === REPORT_SIZE) return buf;
  const frame = Buffer.alloc(REPORT_SIZE);
  buf.copy(frame, 0, 0, Math.min(buf.length, REPORT_SIZE));
  return frame;
}

/**
 * Fake HIDAsync device backed by a socket to the bridge. Implements the surface
 * the Work Louder device-comm layer uses: on('data'|'error'|'close'), write(),
 * close(), read(), getDeviceInfo().
 */
class FakeHIDAsync extends EventEmitter {
  constructor(socketPath) {
    super();
    this.socketPath = socketPath;
    this.sock = null;
    this.connected = false;
    this._rx = Buffer.alloc(0);
    this._queue = [];
    this._connect();
  }

  _connect() {
    const sock = net.createConnection(this.socketPath);
    this.sock = sock;

    sock.on("connect", () => {
      this.connected = true;
      log(`connected to bridge at ${this.socketPath}`);
      for (const f of this._queue) sock.write(f);
      this._queue = [];
    });
    sock.on("data", (chunk) => this._onData(chunk));
    sock.on("error", (err) => {
      log(`socket error: ${err.message}`);
      // Surface as a device error so the app's own reconnect loop kicks in.
      this.emit("error", err);
    });
    sock.on("close", () => {
      this.connected = false;
      this.emit("close");
    });
  }

  _onData(chunk) {
    this._rx = Buffer.concat([this._rx, chunk]);
    while (this._rx.length >= REPORT_SIZE) {
      const frame = this._rx.subarray(0, REPORT_SIZE);
      this._rx = this._rx.subarray(REPORT_SIZE);
      this.emit("data", Buffer.from(frame));
    }
  }

  write(data) {
    const frame = toFrame(data);
    if (this.connected && this.sock) this.sock.write(frame);
    else this._queue.push(frame);
    return Promise.resolve(frame.length);
  }

  read(timeout) {
    return new Promise((resolve) => {
      const onData = (buf) => {
        if (t) clearTimeout(t);
        resolve(buf);
      };
      const t = timeout
        ? setTimeout(() => {
            this.off("data", onData);
            resolve(Buffer.alloc(0));
          }, timeout)
        : null;
      this.once("data", onData);
    });
  }

  getDeviceInfo() {
    return { ...FAKE_DESCRIPTOR };
  }

  // Feature reports are unused by the Codex flow; provide harmless stubs.
  sendFeatureReport() {
    return Promise.resolve(0);
  }
  getFeatureReport() {
    return Promise.resolve(Buffer.alloc(0));
  }
  setNonBlocking() {}
  pause() {}
  resume() {}

  close() {
    try {
      this.sock?.end();
    } catch {
      /* ignore */
    }
    return Promise.resolve();
  }
}

function isFakePath(p) {
  return p === FAKE_PATH || (typeof p === "string" && p.includes(FAKE_PATH));
}

/**
 * Return a patched copy of a real `node-hid` module: `devices()` gains the fake
 * Codex Micro; `HIDAsync.open()` returns the fake device for the fake path and
 * delegates everything else to the real module.
 */
function patchModule(real, opts = {}) {
  const socketPath = opts.socketPath || defaultSocketPath();
  const patched = Object.create(real); // inherit HID, setDriverType, …

  patched.devices = function (...args) {
    log(`devices() called with args: ${JSON.stringify(args)}`);
    let list = [];
    try {
      list = real.devices(...args) || [];
    } catch (err) {
      log(`real.devices error: ${err.message}`);
    }
    const [vid, pid] = args;
    const matches = (!vid || vid === FAKE_DESCRIPTOR.vendorId) && (!pid || pid === FAKE_DESCRIPTOR.productId);
    const result = matches ? list.concat([{ ...FAKE_DESCRIPTOR }]) : list;
    log(`devices() returning ${result.length} device(s)`);
    return result;
  };

  if (typeof real.devicesAsync === "function") {
    patched.devicesAsync = async function (...args) {
      log(`devicesAsync() called with args: ${JSON.stringify(args)}`);
      let list = [];
      try {
        list = (await real.devicesAsync(...args)) || [];
      } catch (err) {
        log(`real.devicesAsync error: ${err.message}`);
      }
      const [vid, pid] = args;
      const matches = (!vid || vid === FAKE_DESCRIPTOR.vendorId) && (!pid || pid === FAKE_DESCRIPTOR.productId);
      const result = matches ? list.concat([{ ...FAKE_DESCRIPTOR }]) : list;
      log(`devicesAsync() returning ${result.length} device(s)`);
      return result;
    };
  }

  const RealHID = real.HID;
  if (RealHID) {
    patched.HID = function (...args) {
      log(`new HID() called with args: ${JSON.stringify(args)}`);
      if (isFakePath(args[0])) {
        return new FakeHIDAsync(socketPath);
      }
      return new RealHID(...args);
    };
    patched.HID.prototype = RealHID.prototype;
  }

  const RealAsync = real.HIDAsync;
  if (RealAsync) {
    patched.HIDAsync = new Proxy(RealAsync, {
      construct(target, argArray) {
        log(`new HIDAsync() called with args: ${JSON.stringify(argArray)}`);
        if (isFakePath(argArray[0])) {
          return new FakeHIDAsync(socketPath);
        }
        return Reflect.construct(target, argArray);
      },
      get(target, prop, receiver) {
        if (prop === "open") {
          return (openPath, openOpts) => {
            log(`HIDAsync.open() called with path: ${openPath}`);
            return isFakePath(openPath)
              ? Promise.resolve(new FakeHIDAsync(socketPath))
              : RealAsync.open(openPath, openOpts);
          };
        }
        return Reflect.get(target, prop, receiver);
      },
    });
  }

  log("node-hid patched");
  return patched;
}

function patchTopologyWatcher(real, opts = {}) {
  log("patching hid-topology-watcher");
  const fakeInterface = {
    path: FAKE_PATH,
    vendorId: FAKE_DESCRIPTOR.vendorId,
    productId: FAKE_DESCRIPTOR.productId,
    usagePage: FAKE_DESCRIPTOR.usagePage,
    usage: FAKE_DESCRIPTOR.usage,
    transport: "usb",
    release: FAKE_DESCRIPTOR.release,
    manufacturer: FAKE_DESCRIPTOR.manufacturer,
    product: FAKE_DESCRIPTOR.product,
    serialNumber: FAKE_DESCRIPTOR.serialNumber,
  };

  return {
    watch(callback) {
      log("hid-topology-watcher.watch() called");
      let realWatcher = null;
      try {
        if (real && typeof real.watch === "function") {
          realWatcher = real.watch(callback);
        }
      } catch (e) {
        log(`real.watch error: ${e.message}`);
      }
      setImmediate(() => {
        try {
          log("triggering hid-topology-watcher callback for fake device");
          callback();
        } catch (e) {
          log(`hid-topology-watcher callback error: ${e.message}`);
        }
      });
      return {
        dispose() {
          log("hid-topology-watcher disposed");
          try {
            realWatcher?.dispose?.();
          } catch {}
        },
      };
    },
    async findCodexMicroInterfaces() {
      log("hid-topology-watcher.findCodexMicroInterfaces() called -> returning fake device");
      let list = [];
      try {
        if (real && typeof real.findCodexMicroInterfaces === "function") {
          list = (await real.findCodexMicroInterfaces()) || [];
        }
      } catch (e) {
        log(`real.findCodexMicroInterfaces error: ${e.message}`);
      }
      return list.concat([fakeInterface]);
    },
  };
}

/** Intercept `require('node-hid')` and `require('hid-topology-watcher')` */
function installHook(opts = {}) {
  const Module = require("node:module");
  const original = Module._load;
  const patchedCache = new WeakMap();

  Module._load = function (request, parent, isMain) {
    const mod = original.apply(this, arguments);
    if (looksLikeNodeHid(request, mod)) {
      if (!patchedCache.has(mod)) patchedCache.set(mod, patchModule(mod, opts));
      return patchedCache.get(mod);
    }
    if (looksLikeHidTopologyWatcher(request, mod)) {
      if (!patchedCache.has(mod)) patchedCache.set(mod, patchTopologyWatcher(mod, opts));
      return patchedCache.get(mod);
    }
    return mod;
  };
  log(`hook installed (socket=${opts.socketPath || defaultSocketPath()})`);
}

function looksLikeNodeHid(request, mod) {
  if (typeof request === "string" && /(^|[\\/])node-hid($|[\\/.])/.test(request)) return true;
  // Shape check as a fallback (bare module already resolved to an object).
  return Boolean(mod && typeof mod.devices === "function" && mod.HIDAsync);
}

function looksLikeHidTopologyWatcher(request, mod) {
  if (typeof request === "string" && /hid[-_]topology[-_]watcher/i.test(request)) return true;
  return Boolean(mod && typeof mod.findCodexMicroInterfaces === "function" && typeof mod.watch === "function");
}

module.exports = {
  REPORT_SIZE,
  FAKE_PATH,
  FAKE_DESCRIPTOR,
  FakeHIDAsync,
  patchModule,
  installHook,
  defaultSocketPath,
};
