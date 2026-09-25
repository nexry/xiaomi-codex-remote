import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { parseArgs } from "../bin/codex-micro-emulator.js";

test("CLI defaults to Xiaomi shim and retains old backends", () => {
  assert.equal(parseArgs([]).input, "xiaomi");
  assert.equal(parseArgs([]).mode, "shim");
  assert.equal(parseArgs(["--xiaomi-source", "ble"]).xiaomiSource, "ble");
  assert.equal(parseArgs(["--xiaomi-source", "miremote"]).xiaomiSource, "miremote");
  assert.equal(parseArgs(["--xiaomi-source", "sayall"]).xiaomiSource, "sayall");
  assert.equal(parseArgs(["--xiaomi-source", "ipc"]).xiaomiSource, "ipc");
});

test("CLI rejects typos, missing values, invalid options and battery ranges", () => {
  for (const args of [["--input"], ["--input", "wrong"], ["--mode", "wrong"], ["--battery", "NaN"],
    ["--battery", "101"], ["--socket"], ["--xiaomi-source", "wrong"], ["--unknown"]]) {
    assert.throws(() => parseArgs(args));
  }
});

test("CLI rejects removed direct HID source", () => {
  assert.throws(
    () => parseArgs(["--xiaomi-source", "hid"]),
    /Invalid --xiaomi-source; expected stdin\|ble\|ipc\|miremote\|sayall/,
  );
});

test("help and invalid args work without hardware or a socket", () => {
  const help = spawnSync(process.execPath, ["bin/xiaomi-codex-remote.js", "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0);
  assert.match(help.stdout, /xiaomi/);
  const invalid = spawnSync(process.execPath, ["bin/xiaomi-codex-remote.js", "--input", "wrong"], { encoding: "utf8" });
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /input/);
});
