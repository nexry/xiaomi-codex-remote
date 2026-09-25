import { EventEmitter } from "node:events";
import net from "node:net";
import { REPORT_SIZE } from "../framing.js";

/**
 * Transport that exchanges fixed-size 64-byte HID reports with the native macOS
 * helper (`native/CodexMicroVirtualHID`) over a Unix domain socket. The helper
 * owns the actual IOKit virtual device; this side owns all the protocol logic.
 *
 * Wire format: raw, back-to-back {@link REPORT_SIZE}-byte frames in both
 * directions. Each frame is `[reportID, channel, length, ...payload]`.
 *
 *   host app ──USB──▶ virtual device ──▶ helper ──socket──▶ this ──▶ emulator
 *   emulator ──▶ this ──socket──▶ helper ──▶ virtual device ──USB──▶ host app
 */
export class SocketTransport extends EventEmitter {
  /**
   * @param {string} socketPath path the helper listens on
   */
  constructor(socketPath) {
    super();
    this.socketPath = socketPath;
    this.socket = null;
    this._rx = Buffer.alloc(0);
  }

  /** Connect to the helper. Resolves once connected. */
  connect() {
    return new Promise((resolve, reject) => {
      const socket = net.createConnection(this.socketPath);
      this.socket = socket;

      socket.on("connect", () => {
        this.emit("open");
        resolve();
      });
      socket.on("data", (chunk) => this._onData(chunk));
      socket.on("error", (err) => {
        this.emit("error", err);
        reject(err);
      });
      socket.on("close", () => this.emit("close"));
    });
  }

  _onData(chunk) {
    this._rx = Buffer.concat([this._rx, chunk]);
    while (this._rx.length >= REPORT_SIZE) {
      const frame = this._rx.subarray(0, REPORT_SIZE);
      this._rx = this._rx.subarray(REPORT_SIZE);
      this.emit("report", Buffer.from(frame));
    }
  }

  write(buf) {
    if (!this.socket || this.socket.destroyed) return;
    // Normalise to exactly REPORT_SIZE so the helper can frame on fixed width.
    let frame = buf;
    if (frame.length !== REPORT_SIZE) {
      const padded = Buffer.alloc(REPORT_SIZE);
      buf.copy(padded, 0, 0, Math.min(buf.length, REPORT_SIZE));
      frame = padded;
    }
    this.socket.write(frame);
  }

  close() {
    this.socket?.end();
  }
}
