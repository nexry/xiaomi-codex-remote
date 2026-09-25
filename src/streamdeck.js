import { Act, Effect, Keys } from "./protocol.js";
import {
  DEFAULT_LAYOUT,
  PLUS_DIALS,
  DIAL_KEYCODES,
  layoutForKeyCount,
  resolveKey,
  keycapAt,
  unpackRgb,
} from "./mapping.js";
import { ICON_TO_LUCIDE } from "./keycaps.js";
import { renderKey, renderLcdZone, canRenderIcons } from "./renderer.js";

// Neutral "light key" background for action keys (white keycaps, dark glyphs).
const ACTION_BG = { r: 236, g: 234, b: 230 };
// An agent key with no active task: a cream keycap, like the unlit hardware —
// not black, which reads as "broken".
const AGENT_OFF_BG = { r: 246, g: 245, b: 241 };
// The periwinkle center dot every agent keycap carries on the real device.
const AGENT_DOT = { r: 112, g: 103, b: 194 };

// LCD dial labels (Stream Deck +). Index = encoder index.
const DIAL_LABELS = {
  [PLUS_DIALS.reason]: { lucide: "brain", text: "Think" },
  [PLUS_DIALS.mic]: { lucide: "mic", text: "Talk" },
  [PLUS_DIALS.codex]: { lucide: "square-terminal", text: "Submit" },
};

/**
 * Drives an Elgato Stream Deck (v7 API) as the Codex Micro's front end.
 *
 * Uses the device's `CONTROLS` model: buttons, encoders (dials), and the LCD
 * segment are discovered at runtime rather than assumed. On a Stream Deck +:
 *   - top row keys   → agent status slots (live state colors + center dot)
 *   - bottom row keys → action keys (Fast / Approve / Reject / Split, with icons)
 *   - dial 0 rotate   → reasoning depth (ENC_CW / ENC_CC); press → ENC_CLK
 *   - dial 1 press    → push-to-talk (mic)
 *   - dial 2 press    → submit (codex)
 *   - LCD strip       → labels for the three active dials
 *
 * `@elgato-stream-deck/node` is an optional dependency, imported dynamically.
 */
export class StreamDeckBackend {
  /**
   * @param {import("./emulator.js").CodexMicroEmulator} emulator
   * @param {object} [opts]
   * @param {string} [opts.path]   specific device path; otherwise first found
   * @param {Array}  [opts.layout] key layout override (see mapping.js)
   */
  constructor(emulator, opts = {}) {
    this.emulator = emulator;
    this.explicitLayout = opts.layout ?? null;
    this.path = opts.path;
    this.deck = null;
    this.layout = opts.layout ?? DEFAULT_LAYOUT;
    this.icons = false;

    this.buttons = []; // button control defs, indexed by control.index
    this.encoders = []; // encoder control defs
    this.lcd = null; // lcd-segment control def
  }

  async start() {
    let mod;
    try {
      mod = await import("@elgato-stream-deck/node");
    } catch {
      throw new Error(
        "@elgato-stream-deck/node is not installed. Run `npm install` (it is an " +
          "optional dependency) or use --input keyboard to test without hardware.",
      );
    }

    const { openStreamDeck, listStreamDecks } = mod;
    let path = this.path;
    if (!path) {
      const found = await listStreamDecks();
      if (!found.length) throw new Error("No Stream Deck found.");
      path = found[0].path;
    }

    this.deck = await openStreamDeck(path);

    // Discover controls (v7 model). NUM_KEYS/ICON_SIZE don't exist in v7.
    const controls = this.deck.CONTROLS ?? [];
    this.buttons = controls.filter((c) => c.type === "button").sort((a, b) => a.index - b.index);
    this.encoders = controls.filter((c) => c.type === "encoder").sort((a, b) => a.index - b.index);
    this.lcd = controls.find((c) => c.type === "lcd-segment") ?? null;

    this.icons = await canRenderIcons();
    this.layout = this.explicitLayout ?? layoutForKeyCount(this.buttons.length);

    await this.deck.clearPanel();

    // v7: both key and dial presses arrive via down/up with a control object.
    this.deck.on("down", (control) => this._onDown(control));
    this.deck.on("up", (control) => this._onUp(control));
    this.deck.on("rotate", (control, amount) => this._onRotate(control, amount));
    this.deck.on("error", () => {});

    this.emulator.on("lighting", (model) => this._paint(model).catch(() => {}));

    await this._paintStatic();
    await this._paintLcdLabels();
    return this.deck;
  }

  // --- input ---------------------------------------------------------------

  _onDown(control) {
    if (control.type === "button") {
      const resolved = resolveKey(control.index, this.layout);
      if (resolved) this.emulator.sendKey(resolved.keycode, Act.PRESS, resolved.agent);
    } else if (control.type === "encoder") {
      this._encoderKey(control.index, Act.PRESS);
    }
  }

  _onUp(control) {
    if (control.type === "button") {
      const resolved = resolveKey(control.index, this.layout);
      if (resolved) this.emulator.sendKey(resolved.keycode, Act.RELEASE, resolved.agent);
    } else if (control.type === "encoder") {
      this._encoderKey(control.index, Act.RELEASE);
    }
  }

  _encoderKey(index, act) {
    if (index === PLUS_DIALS.mic) this.emulator.sendKey(DIAL_KEYCODES.mic, act);
    else if (index === PLUS_DIALS.codex) this.emulator.sendKey(DIAL_KEYCODES.codex, act);
    else if (index === PLUS_DIALS.reason) this.emulator.sendKey(Keys.ENCODER_CLICK, act);
  }

  _onRotate(control, amount) {
    if (control.index !== PLUS_DIALS.reason) return;
    // Turning right (clockwise, amount >= 0) raises reasoning depth; left lowers
    // it. The app maps ENC_CC -> ArrowUp and ENC_CW -> ArrowDown in its effort
    // list, so right sends ENC_CC. Each tick is a single event with act === 2
    // (not a press/release pair) — the only form the app treats as rotation.
    const key = amount >= 0 ? Keys.ENCODER_CCW : Keys.ENCODER_CW;
    for (let i = 0; i < Math.max(1, Math.abs(amount)); i++) {
      this.emulator.sendKey(key, Act.ROTATE);
    }
  }

  // --- output --------------------------------------------------------------

  /** Paint the static action-key icons once; agent keys start as cream keycaps. */
  async _paintStatic() {
    for (let i = 0; i < this.layout.length; i++) {
      if (this.layout[i]?.kind === "action") await this._drawAction(i);
      else if (this.layout[i]?.kind === "agent") await this._fillKey(i, AGENT_OFF_BG, { dot: AGENT_DOT });
    }
  }

  /** Paint agent-slot colors from the latest lighting model. */
  async _paint(model) {
    for (let i = 0; i < this.layout.length; i++) {
      const entry = this.layout[i];
      if (entry?.kind !== "agent") continue;
      const bg = agentBg(model.slots[entry.slot]);
      await this._fillKey(i, bg, { dot: AGENT_DOT });
    }
  }

  async _drawAction(keyIndex) {
    const cap = keycapAt(keyIndex, this.layout);
    const lucide = cap ? ICON_TO_LUCIDE[cap.icon] ?? null : null;
    await this._fillKey(keyIndex, ACTION_BG, { lucide });
  }

  /** Fill one key, using the button's real pixel size for image feedback. */
  async _fillKey(keyIndex, bg, { lucide = null, dot = null } = {}) {
    if (!this.deck) return;
    const button = this.buttons[keyIndex];
    const canImage = button?.feedbackType === "lcd" && this.icons && (lucide || dot);

    if (canImage) {
      const size = button.pixelSize?.width ?? 96;
      const buf = await renderKey({ size, bg, lucide, dot });
      if (buf) {
        try {
          await this.deck.fillKeyBuffer(keyIndex, buf, { format: "rgb" });
          return;
        } catch {
          /* fall through to color */
        }
      }
    }
    try {
      await this.deck.fillKeyColor(keyIndex, bg.r, bg.g, bg.b);
    } catch {
      /* key may not support color feedback */
    }
  }

  /** Draw dial labels on the LCD strip so the touchscreen is lit and useful. */
  async _paintLcdLabels() {
    if (!this.deck || !this.lcd || !this.icons) return;
    if (typeof this.deck.fillLcdRegion !== "function") return;

    const { width, height } = this.lcd.pixelSize;
    const zoneCount = Math.max(this.encoders.length, 1);
    const zoneW = Math.floor(width / zoneCount);

    for (let i = 0; i < zoneCount; i++) {
      const label = DIAL_LABELS[i] ?? { lucide: null, text: "" };
      try {
        const buf = await renderLcdZone({ width: zoneW, height, lucide: label.lucide, text: label.text });
        if (buf) {
          await this.deck.fillLcdRegion(this.lcd.id, i * zoneW, 0, buf, {
            format: "rgb",
            width: zoneW,
            height,
          });
        }
      } catch {
        /* LCD labels are best-effort */
      }
    }
  }

  async stop() {
    if (!this.deck) return;
    try {
      await this.deck.clearPanel();
      await this.deck.close();
    } catch {
      /* ignore */
    }
    this.deck = null;
  }
}

// An agent slot's key color: its live state color when a task is active
// (idle=white, thinking=blue, complete=green, needs-input=amber, error=pink),
// otherwise a cream "unlit keycap".
function agentBg(thread) {
  if (thread && thread.b !== 0 && thread.e !== Effect.off) return unpackRgb(thread.c ?? 0);
  return AGENT_OFF_BG;
}
