import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { encode } from "../src/framing.js";

const url = new URL("../native/xiaomi-codex-remote-gui/Tests/XiaomiCodexRemoteTests/Fixtures/codex-frames.json", import.meta.url);
const fixtures = JSON.parse(await readFile(url, "utf8"));

test("shared Codex frame fixtures match the JavaScript encoder", () => {
  for (const fixture of fixtures) {
    assert.deepEqual(
      encode(fixture.message, fixture.channel).map((frame) => frame.toString("hex")),
      fixture.frames,
      fixture.name,
    );
  }
});
