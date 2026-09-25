import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { CodexMicroEmulator } from "../src/emulator.js";
import { XiaomiRemoteBackend } from "../src/xiaomi/backend.js";
import { createMapping, resolveKey } from "../src/xiaomi/mapping.js";

function setup(options = {}) {
  const emulator = new CodexMicroEmulator();
  const notes = [];
  emulator.on("send", (line) => notes.push(JSON.parse(line).p));
  return { notes, backend: new XiaomiRemoteBackend(emulator, options) };
}
const event = (key, action) => ({ key, action });

test("default mapping matches existing protocol, with unsupported directions disabled", () => {
  const mapping = createMapping();
  assert.deepEqual(resolveKey("home", mapping), { kind: "key", keycode: "AG00", agent: 0 });
  assert.deepEqual(resolveKey("voice", mapping), { kind: "key", keycode: "ACT10", agent: null });
  assert.equal(resolveKey("volume_up", mapping).keycode, "ENC_CC");
  assert.deepEqual(resolveKey("up", mapping), { kind: "joystick", angle: 0.75, agent: null });
  for (const key of ["power", "unknown", "toString", "__proto__"]) assert.equal(resolveKey(key, mapping), null);
});

test("mapping overrides merge with defaults, can disable keys, and reject invalid protocol targets", () => {
  const mapping = createMapping({ home: { kind: "key", keycode: "AG05" }, back: null });
  assert.equal(resolveKey("home", mapping).agent, 5);
  assert.equal(resolveKey("back", mapping), null);
  assert.equal(resolveKey("voice", mapping).keycode, "ACT10");
  for (const overrides of [[], null, { ok: { kind: "key", keycode: "BOGUS" } },
    { ok: { kind: "key", keycode: "ENC_CC" } }, { ok: { kind: "rotate", keycode: "ACT10" } },
    { ok: { kind: "key", keycode: "ACT10", typo: 1 } }]) {
    assert.throws(() => createMapping(overrides), /mapping/i);
  }
  assert.equal(resolveKey("home", createMapping()).agent, 0);
});

test("press/release forwards to emulator; duplicate press, repeat and orphan release do not", async () => {
  const { backend, notes } = setup();
  assert.equal(backend.handleEvent(event("home", "press")), false);
  await backend.start();
  for (const action of ["release", "press", "press", "repeat", "release", "release"]) backend.handleEvent(event("home", action));
  assert.deepEqual(notes, [{ k: "AG00", act: 1, ag: 0 }, { k: "AG00", act: 0, ag: 0 }]);
  await backend.stop();
});

test("voice tracks hold until release and rotations emit act=2 without release", async () => {
  const { backend, notes } = setup();
  await backend.start();
  for (const action of ["press", "repeat", "release"]) backend.handleEvent(event("voice", action));
  for (const action of ["repeat", "press", "press", "repeat", "release"]) backend.handleEvent(event("volume_up", action));
  backend.handleEvent(event("volume_down", "press"));
  await backend.stop();
  assert.deepEqual(notes, [{ k: "ACT10", act: 1 }, { k: "ACT10", act: 0 },
    { k: "ENC_CC", act: 2 }, { k: "ENC_CC", act: 2 }, { k: "ENC_CW", act: 2 }]);
});

test("invalid events never send notifications", async () => {
  const { backend, notes } = setup();
  await backend.start();
  for (const value of [null, {}, "home", event("unknown", "press"), event("ok", "hold")]) {
    assert.equal(backend.handleEvent(value), false);
  }
  assert.deepEqual(notes, []);
  await backend.stop();
});

test("source lifecycle supports disconnect, stop, restart and listener cleanup", async () => {
  const source = new EventEmitter();
  let starts = 0, stops = 0;
  source.start = async () => { starts++; };
  source.stop = async () => { stops++; };
  const { backend, notes } = setup({ source });
  await backend.start();
  await backend.start();
  source.emit("key", event("ok", "press"));
  source.emit("disconnect");
  source.emit("key", event("voice", "press"));
  await backend.stop();
  await backend.stop();
  assert.deepEqual(notes, [{ k: "ENC_CLK", act: 1 }, { k: "ENC_CLK", act: 0 }, { k: "ACT10", act: 1 }, { k: "ACT10", act: 0 }]);
  assert.equal(starts, 1);
  assert.equal(stops, 1);
  assert.equal(source.listenerCount("key"), 0);
  await backend.start();
  source.emit("key", event("home", "press"));
  await backend.stop();
  assert.equal(notes.at(-1).act, 0);
});

test("failed source startup cleans listeners and pressed state", async () => {
  const source = new EventEmitter();
  source.start = async () => { source.emit("key", event("voice", "press")); throw new Error("unavailable"); };
  source.stop = async () => {};
  const { backend, notes } = setup({ source });
  await assert.rejects(backend.start(), /unavailable/);
  assert.equal(source.listenerCount("key"), 0);
  assert.equal(notes.at(-1).act, 0);
  assert.equal(backend.handleEvent(event("home", "press")), false);
});

test("source errors release held buttons and surface to caller", async () => {
  const source = new EventEmitter();
  source.start = async () => {};
  const { backend, notes } = setup({ source });
  const errors = [];
  backend.on("error", (err) => errors.push(err.message));
  await backend.start();
  source.emit("key", event("voice", "press"));
  source.emit("error", new Error("disconnected"));
  assert.equal(notes.at(-1).act, 0);
  assert.deepEqual(errors, ["disconnected"]);
  await backend.stop();
});
