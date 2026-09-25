// Integration test for the node-hid shim, exercised without the ChatGPT app.
//
// It stands up the real bridge (SocketServerTransport + emulator) on a temp
// socket, then loads the real shim (patch.cjs) and drives it exactly as the app
// would: enumerate devices, open the fake Codex Micro, write a framed
// device.status request, and assert the framed response comes back.

import { test } from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

import { CodexMicroEmulator } from "../src/emulator.js";
import { Link } from "../src/link.js";
import { SocketServerTransport } from "../src/transports/socket-server.js";
import { encode, Reassembler, Channel } from "../src/framing.js";
import { Method } from "../src/protocol.js";

const require = createRequire(import.meta.url);
const shim = require("../shim/patch.cjs");

function tmpSocket() {
  // Short path — macOS sun_path is ~104 chars.
  const rnd = Math.abs(Number(process.hrtime.bigint() % 1000000n));
  return path.join(os.tmpdir(), `cmx-${rnd}.sock`);
}

test("shim: fake device is discoverable and round-trips device.status", async () => {
  const socketPath = tmpSocket();

  // Bridge side.
  const emulator = new CodexMicroEmulator({ battery: 55, charging: false });
  const server = new SocketServerTransport(socketPath);
  await server.listen();
  new Link(emulator, server);

  // App side: the real shim, patched over a stub node-hid.
  const stubRealNodeHid = {
    devices: () => [{ vendorId: 0x1234, productId: 0x1, path: "real-device" }],
    HIDAsync: { open: async () => ({ isReal: true }) },
  };
  const patched = shim.patchModule(stubRealNodeHid, { socketPath });

  // 1) Discovery includes the fake Codex Micro with the right descriptor.
  const found = patched.devices();
  const codex = found.find((d) => d.vendorId === 0x303a && d.productId === 0x8360);
  assert.ok(codex, "fake Codex Micro should appear in devices()");
  assert.equal(codex.usagePage, 0xff00);
  assert.equal(codex.manufacturer, "Work Louder");
  assert.equal(codex.release & 0x0003, 0, "release low bits clear => USB");

  // Real devices still pass through.
  assert.ok(found.some((d) => d.path === "real-device"));

  // 2) Opening a non-fake path delegates to the real module.
  const real = await patched.HIDAsync.open("real-device");
  assert.equal(real.isReal, true);

  // 3) Open the fake device and exchange a framed device.status request.
  const dev = await patched.HIDAsync.open(codex.path);
  await once(dev, "data-ready-or-connect", dev, socketPath); // ensure socket up

  const reasm = new Reassembler();
  const responsePromise = new Promise((resolve) => {
    dev.on("data", (buf) => {
      for (const { channel, message } of reasm.push(buf)) {
        if (channel === Channel.RPC) resolve(JSON.parse(message));
      }
    });
  });

  // Send bare JSON with no trailing newline, exactly as the app does.
  for (const report of encode(JSON.stringify({ method: Method.DEVICE_STATUS, id: 77 }), Channel.RPC)) {
    await dev.write(report);
  }

  const res = await responsePromise;
  assert.equal(res.id, 77);
  assert.equal(res.result.battery, 55);
  assert.equal(res.result.is_charging, false);

  await dev.close();
  server.close();
});

// Wait until the fake device's socket has actually connected to the bridge.
function once(dev, _label, device, _socketPath) {
  return new Promise((resolve) => {
    if (device.connected) return resolve();
    const t = setInterval(() => {
      if (device.connected) {
        clearInterval(t);
        resolve();
      }
    }, 5);
  });
}
