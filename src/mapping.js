import { Keys } from "./protocol.js";
import { DEFAULT_ACTION_KEYS, KEYCAP } from "./keycaps.js";

// Maps physical Stream Deck keys to Codex Micro controls.
//
// Each layout entry is one of:
//   { kind: "agent",  slot }                    agent/thread key (AG00..AG05)
//   { kind: "action", keycode, keycap }         action key (ACT06..ACT12)
//   { kind: "empty" }                           unused
//
// `slot` keys receive per-thread state lighting from v.oai.thstatus and show a
// colored background. `action` keys show their keycap icon on a light key, like
// the hardware. The default targets a 15-key deck (5×3); override for other
// models (Mini 6, XL 32, Plus 8, …).

/** Full-size layout (15-key decks): six agent slots, then six default actions. */
function fullLayout() {
  const layout = [];
  for (let slot = 0; slot < Keys.AGENT.length; slot++) {
    layout.push({ kind: "agent", slot });
  }
  for (const a of DEFAULT_ACTION_KEYS) {
    layout.push({ kind: "action", keycode: a.keycode, keycap: a.keycap });
  }
  return layout;
}

/**
 * Stream Deck + layout (8 keys, 2×4):
 *   top row    = agent status slots 0–3 (colored keys with a center dot)
 *   bottom row = the four action keys Fast / Approve / Reject / Split
 * The remaining Codex controls move to the dials (see {@link PLUS_DIALS}):
 * dial 0 = reasoning depth, dial 1 press = push-to-talk (mic), dial 2 press =
 * submit (codex). Flip top/bottom by swapping the two halves below.
 */
function plusLayout() {
  return [
    { kind: "agent", slot: 0 },
    { kind: "agent", slot: 1 },
    { kind: "agent", slot: 2 },
    { kind: "agent", slot: 3 },
    { kind: "action", keycode: "ACT06", keycap: "FAST" },
    { kind: "action", keycode: "ACT07", keycap: "APPR" },
    { kind: "action", keycode: "ACT08", keycap: "REJ" },
    { kind: "action", keycode: "ACT09", keycap: "SPLIT" },
  ];
}

export const DEFAULT_LAYOUT = fullLayout();
export const PLUS_LAYOUT = plusLayout();

/**
 * Dial roles on a Stream Deck + (by encoder index):
 *   reason — rotate drives reasoning depth (ENC_CW/ENC_CC); press = ENC_CLK
 *   mic    — press-and-hold = push-to-talk (MIC / ACT10)
 *   codex  — press = submit  (CODEX / ACT12)
 */
export const PLUS_DIALS = Object.freeze({
  reason: 0,
  mic: 1,
  codex: 2,
});

/** Keycodes for the controls that live on the dials rather than the keys. */
export const DIAL_KEYCODES = Object.freeze({
  mic: "ACT10", // push-to-talk (the wide mic key, ACT10/ACT11)
  codex: "ACT12", // submit
});

/**
 * Pick a layout for a deck by its key count. Falls back to the full layout,
 * truncated to fit, for unrecognised sizes (Mini 6, XL 32, …).
 */
export function layoutForKeyCount(keys) {
  if (keys === 8) return PLUS_LAYOUT;
  if (keys >= 12) return DEFAULT_LAYOUT;
  return DEFAULT_LAYOUT.slice(0, keys);
}

/**
 * Agent slots that don't fit on the keys and should be shown on the LCD strip,
 * given a layout. Returns the slot numbers not already placed on a key.
 */
export function overflowSlots(layout, slotCount = Keys.AGENT.length) {
  const onKeys = new Set(
    layout.filter((e) => e.kind === "agent").map((e) => e.slot),
  );
  const out = [];
  for (let s = 0; s < slotCount; s++) if (!onKeys.has(s)) out.push(s);
  return out;
}

/**
 * Resolve a Stream Deck key index to what it should send.
 * @param {number} keyIndex
 * @param {typeof DEFAULT_LAYOUT} [layout]
 * @returns {{keycode: string, agent: number|null}|null}
 */
export function resolveKey(keyIndex, layout = DEFAULT_LAYOUT) {
  const entry = layout[keyIndex];
  if (!entry) return null;
  if (entry.kind === "agent") {
    return { keycode: Keys.AGENT[entry.slot], agent: entry.slot };
  }
  if (entry.kind === "action") {
    return { keycode: entry.keycode, agent: null };
  }
  return null;
}

/** The keycap catalogue entry for a layout slot, if it is an action key. */
export function keycapAt(keyIndex, layout = DEFAULT_LAYOUT) {
  const entry = layout[keyIndex];
  if (!entry || entry.kind !== "action") return null;
  return KEYCAP[entry.keycap] ?? null;
}

/** Unpack a firmware packed-RGB integer into { r, g, b } bytes. */
export function unpackRgb(color) {
  const c = color >>> 0;
  return { r: (c >> 16) & 0xff, g: (c >> 8) & 0xff, b: c & 0xff };
}
