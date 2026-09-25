import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  AdpcmDecoder,
  createWavHeader,
  IMA_INDEX_TABLE,
  IMA_STEP_TABLE,
  ATVV_AUDIO_CONSTANTS,
} from "../src/xiaomi/audio.js";
import {
  AtvvSession,
  ATVV_UUIDS,
  ATVV_COMMANDS,
  ATVV_CTL_OPCODES,
  ATVV_CODECS,
} from "../src/xiaomi/atvv.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixturePath = path.join(__dirname, "fixtures", "rc003-voice.json");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

test("audio constants and tables are properly configured", () => {
  assert.equal(ATVV_AUDIO_CONSTANTS.SAMPLE_RATE, 16000);
  assert.equal(ATVV_AUDIO_CONSTANTS.CHANNELS, 1);
  assert.equal(ATVV_AUDIO_CONSTANTS.BITS_PER_SAMPLE, 16);
  assert.equal(IMA_INDEX_TABLE.length, 16);
  assert.equal(IMA_STEP_TABLE.length, 89);
  assert.equal(IMA_STEP_TABLE[0], 7);
  assert.equal(IMA_STEP_TABLE[88], 32767);
});

test("AdpcmDecoder decodes captured 120-byte RC003 frame to 240 16-bit samples", () => {
  const decoder = new AdpcmDecoder();
  const rawPkt = new Uint8Array(fixture.audio_frames[0]);
  assert.equal(rawPkt.length, 120);

  const result = decoder.decode(rawPkt);
  assert.equal(result.sampleRate, 16000);
  assert.equal(result.channels, 1);
  assert.equal(result.samples.length, 240); // 120 bytes * 2 samples per byte
  assert(result.samples instanceof Int16Array);

  // Decoded samples are non-trivial valid 16-bit integers
  const nonZero = Array.from(result.samples).filter((s) => s !== 0);
  assert(nonZero.length > 50, "Samples should not be all zeroes");
});

test("AdpcmDecoder handles reset and sync", () => {
  const decoder = new AdpcmDecoder();
  decoder.sync(500, 10);
  assert.equal(decoder.predict, 500);
  assert.equal(decoder.predictIdx, 10);

  decoder.reset();
  assert.equal(decoder.predict, 0);
  assert.equal(decoder.predictIdx, 0);
});

test("createWavHeader produces valid 44-byte RIFF header", () => {
  const pcmBytes = 240 * 2; // 480 bytes
  const header = createWavHeader(pcmBytes, { sampleRate: 16000, channels: 1, bitsPerSample: 16 });
  assert.equal(header.length, 44);

  // Check RIFF / WAVE markers
  const text = Buffer.from(header).toString("latin1");
  assert.equal(text.slice(0, 4), "RIFF");
  assert.equal(text.slice(8, 12), "WAVE");
  assert.equal(text.slice(12, 16), "fmt ");
  assert.equal(text.slice(36, 40), "data");

  const view = new DataView(header.buffer);
  assert.equal(view.getUint32(4, true), 36 + pcmBytes);
  assert.equal(view.getUint16(20, true), 1); // PCM
  assert.equal(view.getUint16(22, true), 1); // 1 channel
  assert.equal(view.getUint32(24, true), 16000); // 16kHz
  assert.equal(view.getUint32(40, true), pcmBytes);
});

test("AtvvSession negotiates CAPS and manages mic session", async () => {
  const written = [];
  const audioChunks = [];
  const events = [];

  const session = new AtvvSession({
    writeControl: async (pkt) => {
      written.push(Array.from(pkt));
    },
    onEncodedAudio: (pkt) => {
      audioChunks.push(pkt);
    },
  });

  session.on("caps", (caps) => events.push({ type: "caps", caps }));
  session.on("audio_start", (ev) => events.push({ type: "audio_start", ev }));
  session.on("audio_stop", (ev) => events.push({ type: "audio_stop", ev }));

  // Start session sends GET_CAPS
  await session.start();
  assert.equal(written.length, 1);
  assert.deepEqual(written[0], fixture.commands.get_caps);

  // Push CAPS_RESP from fixture
  session.pushControl(new Uint8Array(fixture.ctl_responses.caps_resp));
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "caps");
  assert.equal(events[0].caps.version, "0.4");
  assert.equal(events[0].caps.codecs, ATVV_CODECS.ADPCM_16K);

  // Open Mic sends MIC_OPEN
  await session.openMic(ATVV_CODECS.ADPCM_16K);
  assert.equal(written.length, 2);
  assert.deepEqual(written[1], fixture.commands.mic_open_16k);
  assert.equal(session.micOpen, true);

  // Push AUDIO_START from fixture
  session.pushControl(new Uint8Array(fixture.ctl_responses.audio_start));
  assert.equal(events.length, 2);
  assert.equal(events[1].type, "audio_start");

  // Push audio frame from fixture
  const frame = new Uint8Array(fixture.audio_frames[0]);
  session.pushAudio(frame);
  assert.equal(audioChunks.length, 1);
  assert.deepEqual(Array.from(audioChunks[0]), Array.from(frame));

  // Close Mic sends MIC_CLOSE
  await session.closeMic();
  assert.equal(written.length, 3);
  assert.deepEqual(written[2], fixture.commands.mic_close);
  assert.equal(session.micOpen, false);

  // Push AUDIO_STOP from fixture
  session.pushControl(new Uint8Array(fixture.ctl_responses.audio_stop));
  assert.equal(events.length, 3);
  assert.equal(events[2].type, "audio_stop");

  await session.stop();
  assert.equal(session.active, false);
});
