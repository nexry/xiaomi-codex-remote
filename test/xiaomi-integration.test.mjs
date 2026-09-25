import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import net from "node:net";
import { mkdtemp, rm, access, writeFile } from "node:fs/promises";
import { once } from "node:events";
import { Reassembler, REPORT_SIZE } from "../src/framing.js";

async function launch(t, extra = []) {
  const dir = await mkdtemp("/tmp/xcr-");
  const socket = `${dir}/bridge.sock`;
  const config = `${dir}/mapping.json`;
  await writeFile(config, JSON.stringify({ home: { kind: "key", keycode: "AG05" } }));
  const child = spawn(process.execPath, ["bin/xiaomi-codex-remote.js", "--socket", socket, "--xiaomi-config", config, ...extra], { stdio: ["pipe", "pipe", "pipe"] });
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exited = once(child, "exit");
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await exited; }
    await rm(dir, { recursive: true, force: true });
  });
  return { child, exited, socket, stderr: () => stderr };
}
async function until(predicate, label) {
  const deadline = Date.now() + 3000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${label}`);
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

test("Xiaomi CLI forwards configured press/release and rotary ticks over unchanged framing/socket", { timeout: 8000 }, async (t) => {
  const app = await launch(t);
  await until(() => app.stderr().includes("input ready"), "CLI ready");
  const peer = net.createConnection(app.socket);
  t.after(() => peer.destroy());
  await once(peer, "connect");
  const notes = [];
  const reassembler = new Reassembler();
  let pending = Buffer.alloc(0);
  peer.on("data", (chunk) => {
    pending = Buffer.concat([pending, chunk]);
    while (pending.length >= REPORT_SIZE) {
      for (const { message } of reassembler.push(pending.subarray(0, REPORT_SIZE))) notes.push(JSON.parse(message));
      pending = pending.subarray(REPORT_SIZE);
    }
  });
  for (const [key, action] of [["home", "press"], ["home", "release"], ["volume_up", "press"], ["volume_up", "release"], ["voice", "press"]]) {
    app.child.stdin.write(JSON.stringify({ key, action }) + "\n");
  }
  await until(() => notes.length === 4, "key notifications");
  assert.deepEqual(notes.map((note) => note.p), [{ k: "AG05", act: 1, ag: 5 }, { k: "AG05", act: 0, ag: 5 }, { k: "ENC_CC", act: 2 }, { k: "ACT10", act: 1 }]);
  assert.ok(notes.every((note) => note.m === "v.oai.hid"));
  app.child.stdin.end();
  const [code] = await app.exited;
  assert.equal(code, 0, app.stderr());
  await until(() => notes.length === 5, "EOF releases voice key");
  assert.deepEqual(notes.at(-1).p, { k: "ACT10", act: 0 });
  await assert.rejects(access(app.socket));
});

test("ble reports unsupported and cleans socket", { timeout: 8000 }, async (t) => {
  const app = await launch(t, ["--xiaomi-source", "ble"]);
  const [code] = await app.exited;
  assert.equal(code, 1);
  assert.match(app.stderr(), /not implemented/);
  await assert.rejects(access(app.socket));
});

test("malformed stdin exits nonzero and cleans socket", { timeout: 8000 }, async (t) => {
  const app = await launch(t);
  await until(() => app.stderr().includes("input ready"), "CLI ready");
  app.child.stdin.write("bad JSON\n");
  const [code] = await app.exited;
  assert.equal(code, 1);
  assert.match(app.stderr(), /JSON/);
  await assert.rejects(access(app.socket));
});

test("SIGTERM closes a waiting Xiaomi bridge", { timeout: 8000 }, async (t) => {
  const app = await launch(t);
  await until(() => app.stderr().includes("input ready"), "CLI ready");
  app.child.kill("SIGTERM");
  const [code] = await app.exited;
  assert.equal(code, 0);
  await assert.rejects(access(app.socket));
});
