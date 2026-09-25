import { Keys } from "./protocol.js";

/**
 * Hardware-free input source: read single keypresses from the terminal and turn
 * them into Codex Micro key events. Useful for exercising the host bridge
 * without a Stream Deck attached.
 *
 *   1..6  -> tap agent slot 0..5   (AG00..AG05)
 *   q..u  -> tap action ACT06..ACT12
 *   [ / ] -> encoder CCW / CW
 *   \     -> encoder click
 *   ctrl-c-> quit
 */
export class KeyboardInput {
  /** @param {import("./emulator.js").CodexMicroEmulator} emulator */
  constructor(emulator) {
    this.emulator = emulator;
    this._onData = this._onData.bind(this);
  }

  start() {
    const stdin = process.stdin;
    if (!stdin.isTTY) {
      throw new Error("Keyboard input requires an interactive TTY.");
    }
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding("utf8");
    stdin.on("data", this._onData);

    process.stderr.write(
      "Keyboard input: [1-6]=agents  [q-u]=actions  [ / ]=encoder  \\=click  ctrl-c=quit\n",
    );
  }

  _onData(str) {
    if (str === "") {
      // ctrl-c
      process.emit("SIGINT");
      return;
    }

    const agentIdx = "123456".indexOf(str);
    if (agentIdx !== -1) return this.emulator.tapAgent(agentIdx);

    const actionIdx = "qwertyu".indexOf(str);
    if (actionIdx !== -1 && actionIdx < Keys.ACTION.length) {
      return this.emulator.tapAction(Keys.ACTION[actionIdx]);
    }

    if (str === "[") return this._tapEncoder(Keys.ENCODER_CCW);
    if (str === "]") return this._tapEncoder(Keys.ENCODER_CW);
    if (str === "\\") return this._tapEncoder(Keys.ENCODER_CLICK);
  }

  _tapEncoder(key) {
    this.emulator.sendKey(key, 1);
    this.emulator.sendKey(key, 0);
  }

  stop() {
    const stdin = process.stdin;
    stdin.off("data", this._onData);
    if (stdin.isTTY) stdin.setRawMode(false);
    stdin.pause();
  }
}
