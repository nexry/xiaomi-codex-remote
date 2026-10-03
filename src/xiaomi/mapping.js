import { Keys } from "../protocol.js";

// Logical RC003 names, NOT measured HID usages. Hardware decoding is a later step.
export const DEFAULT_MAPPING = Object.freeze(Object.fromEntries(Object.entries({
  home: { kind: "key", keycode: Keys.AGENT[0] },
  menu: { kind: "key", keycode: Keys.AGENT[1] },
  back: { kind: "key", keycode: "ACT08" },
  ok: { kind: "key", keycode: "ACT12" },
  voice: { kind: "key", keycode: "ACT10" },
  // Match upstream Stream Deck's reasoning-up direction (ENC_CC).
  volume_up: { kind: "rotate", keycode: Keys.ENCODER_CCW },
  volume_down: { kind: "rotate", keycode: Keys.ENCODER_CW },
  up: { kind: "joystick", angle: 0.75 },
  down: { kind: "joystick", angle: 0.25 },
  left: { kind: "joystick", angle: 0.5 },
  right: { kind: "joystick", angle: 0 },
  power: null,
}).map(([key, value]) => [key, value && Object.freeze(value)])));

const buttonCodes = new Set([...Keys.AGENT, ...Keys.ACTION, Keys.ENCODER_CLICK]);
const rotationCodes = new Set([Keys.ENCODER_CCW, Keys.ENCODER_CW]);

/** Merge validated overrides. null disables a key; agent is derived from keycode. */
export function createMapping(overrides = {}) {
  if (!overrides || typeof overrides !== "object" || Array.isArray(overrides)) {
    throw new TypeError("Xiaomi mapping must be an object of logical key names to bindings.");
  }
  const mapping = Object.create(null);
  for (const [key, entry] of Object.entries({ ...DEFAULT_MAPPING, ...overrides })) {
    if (entry === null) { mapping[key] = null; continue; }
    if (!/^[a-z][a-z0-9_]*$/.test(key) || !entry || typeof entry !== "object" ||
        Object.keys(entry).some((field) => !["kind", "keycode", "angle"].includes(field)) ||
        (entry.kind === "key" && !buttonCodes.has(entry.keycode)) ||
        (entry.kind === "rotate" && !rotationCodes.has(entry.keycode)) ||
        (entry.kind === "joystick" && (typeof entry.angle !== "number" || entry.angle < 0 || entry.angle > 1)) ||
        !["key", "rotate", "joystick"].includes(entry.kind)) {
      throw new TypeError(`Invalid Xiaomi mapping for ${key}; use {kind, keycode} or {kind: 'joystick', angle} or null.`);
    }
    const slot = entry.keycode ? Keys.AGENT.indexOf(entry.keycode) : -1;
    mapping[key] = Object.freeze({ ...entry, agent: slot < 0 ? null : slot });
  }
  return Object.freeze(mapping);
}

const defaults = createMapping();
export function resolveKey(key, mapping = defaults) {
  return typeof key === "string" && Object.hasOwn(mapping, key) ? mapping[key] : null;
}
