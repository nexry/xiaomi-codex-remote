import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { IpcSource } from "../src/xiaomi/ipc.js";

test("IpcSource receives and parses valid key events over Unix socket", async () => {
  const socketPath = path.join(os.tmpdir(), `test-ipc-${Date.now()}.sock`);
  const source = new IpcSource({ socketPath });

  await source.start();

  const events = [];
  source.on("key", (ev) => events.push(ev));

  // Connect client
  const client = net.createConnection(socketPath);
  await new Promise((resolve) => client.on("connect", resolve));

  // Send events
  client.write(JSON.stringify({ key: "voice", action: "press" }) + "\n");
  client.write(JSON.stringify({ key: "voice", action: "release" }) + "\n");
  client.write("invalid json\n");
  client.write(JSON.stringify({ key: "ok", action: "press" }) + "\n");

  await new Promise((resolve) => setTimeout(resolve, 50));

  assert.equal(events.length, 3);
  assert.deepEqual(events[0], { key: "voice", action: "press" });
  assert.deepEqual(events[1], { key: "voice", action: "release" });
  assert.deepEqual(events[2], { key: "ok", action: "press" });

  let disconnected = false;
  source.on("disconnect", () => {
    disconnected = true;
  });

  client.end();
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(disconnected, true);

  await source.stop();
});
