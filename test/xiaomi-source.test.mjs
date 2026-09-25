import { test } from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import { StdinSource } from "../src/xiaomi/stdin.js";
import { BleSource } from "../src/xiaomi/ble.js";

test("stdin handles split JSON lines and EOF without owning process.stdin", async () => {
  const stream = new PassThrough();
  const source = new StdinSource(stream);
  const keys = [];
  let ended = 0;
  source.on("key", (key) => keys.push(key));
  source.on("end", () => ended++);
  await source.start();
  stream.write('\n{"key":"home",');
  stream.end('"action":"press"}\n{"key":"home","action":"release"}\n');
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(keys, [{ key: "home", action: "press" }, { key: "home", action: "release" }]);
  assert.equal(ended, 1);
  await source.stop();
  assert.equal(stream.listenerCount("error"), 0);
});

test("malformed input surfaces an actionable error and stop removes listeners", async () => {
  const stream = new PassThrough();
  const source = new StdinSource(stream);
  const errors = [];
  source.on("error", (err) => errors.push(err.message));
  await source.start();
  stream.write('not-json\n');
  assert.match(errors[0], /JSON/);
  await source.stop();
  assert.equal(stream.listenerCount("data"), 0);
  assert.equal(stream.destroyed, false);
});

test("BleSource placeholder fails explicitly instead of pretending to connect", async () => {
  const source = new BleSource();
  await assert.rejects(source.start(), /not implemented/);
  await source.stop();
});
