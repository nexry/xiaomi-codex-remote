// Unit tests for the Stream Deck backend's input mapping that don't need a
// physical device: they call the handlers directly and assert the emitted
// v.oai.hid notifications. Guards the encoder-rotation contract in particular.

import { test } from "node:test";
import assert from "node:assert/strict";

import { CodexMicroEmulator } from "../src/emulator.js";
import { StreamDeckBackend } from "../src/streamdeck.js";
import { PLUS_DIALS, DIAL_KEYCODES, PLUS_LAYOUT } from "../src/mapping.js";
import { Notify } from "../src/protocol.js";

/** Collect every notification the emulator emits. */
function capture(emulator) {
  const notes = [];
  emulator.on("send", (line) => {
    const obj = JSON.parse(line);
    if (obj.m === Notify.HID) notes.push(obj.p);
  });
  return notes;
}

test("reasoning dial rotation emits ENC_CW/ENC_CC with act 2 (single tick)", () => {
  const emulator = new CodexMicroEmulator();
  const backend = new StreamDeckBackend(emulator);
  const notes = capture(emulator);

  backend._onRotate({ type: "encoder", index: PLUS_DIALS.reason }, 1); // right -> raise
  backend._onRotate({ type: "encoder", index: PLUS_DIALS.reason }, -1); // left  -> lower

  // Right (clockwise) raises reasoning depth, which the app reads as ENC_CC.
  assert.deepEqual(notes, [
    { k: "ENC_CC", act: 2 },
    { k: "ENC_CW", act: 2 },
  ]);
});

test("rotating other dials does nothing", () => {
  const emulator = new CodexMicroEmulator();
  const backend = new StreamDeckBackend(emulator);
  const notes = capture(emulator);
  backend._onRotate({ type: "encoder", index: PLUS_DIALS.mic }, 1);
  assert.equal(notes.length, 0);
});

test("dial presses map to push-to-talk and submit", () => {
  const emulator = new CodexMicroEmulator();
  const backend = new StreamDeckBackend(emulator);
  const notes = capture(emulator);

  backend._onDown({ type: "encoder", index: PLUS_DIALS.mic });
  backend._onUp({ type: "encoder", index: PLUS_DIALS.mic });
  backend._onDown({ type: "encoder", index: PLUS_DIALS.codex });
  backend._onUp({ type: "encoder", index: PLUS_DIALS.codex });

  assert.deepEqual(notes, [
    { k: DIAL_KEYCODES.mic, act: 1 },
    { k: DIAL_KEYCODES.mic, act: 0 },
    { k: DIAL_KEYCODES.codex, act: 1 },
    { k: DIAL_KEYCODES.codex, act: 0 },
  ]);
});

test("top-row keys send agent slots, bottom-row keys send actions", () => {
  const emulator = new CodexMicroEmulator();
  const backend = new StreamDeckBackend(emulator, { layout: PLUS_LAYOUT });
  const notes = capture(emulator);

  backend._onDown({ type: "button", index: 0 }); // agent slot 0
  backend._onDown({ type: "button", index: 4 }); // first action (FAST / ACT06)

  assert.equal(notes[0].k, "AG00");
  assert.equal(notes[0].ag, 0);
  assert.equal(notes[1].k, "ACT06");
});
