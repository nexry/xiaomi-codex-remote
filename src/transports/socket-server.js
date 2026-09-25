import { EventEmitter } from "node:events";
import net from "node:net";
import fs from "node:fs";
import { REPORT_SIZE } from "../framing.js";

/**
 * Bridge-side transport for the node-hid shim. The bridge *listens*; the shim
 * injected into the ChatGPT app *connects*. Exchanges fixed 64-byte HID report
 * frames, identical to {@link SocketTransport}, so the emulator and Stream Deck
 * backend are unchanged — only which end opens the socket differs.
 *
 * The bridge is long-lived and should be started before the app launches. If
 * the app restarts, the shim reconnects and the last connection wins.
 */
export class SocketServerTransport extends EventEmitter {
  /** @param {string} socketPath path to listen on */
  constructor(socketPath) {
    super();
    this.socketPath = socketPath;
    this.server = null;
    this.client = null;
    this._rx = Buffer.alloc(0);
  }

  /** Begin listening. Resolves once the socket is bound. */
  listen() {
    return new Promise((resolve, reject) => {
      try {
        if (fs.existsSync(this.socketPath)) fs.unlinkSync(this.socketPath);
      } catch {
        /* ignore */
      }

      const server = net.createServer((socket) => {
        // Newest connection wins; drop any previous shim.
        if (this.client && !this.client.destroyed) this.client.destroy();
        this.client = socket;
        this._rx = Buffer.alloc(0);
        this.emit("open");

        socket.on("data", (chunk) => this._onData(chunk));
        socket.on("error", (err) => this.emit("error", err));
        socket.on("close", () => {
          if (this.client === socket) this.client = null;
          this.emit("client-close");
        });
      });

      server.on("error", reject);
      server.listen(this.socketPath, () => {
        this.server = server;
        resolve();
      });
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
    if (!this.client || this.client.destroyed) return;
    let frame = buf;
    if (frame.length !== REPORT_SIZE) {
      const padded = Buffer.alloc(REPORT_SIZE);
      buf.copy(padded, 0, 0, Math.min(buf.length, REPORT_SIZE));
      frame = padded;
    }
    this.client.write(frame);
  }

  close() {
    this.client?.destroy();
    this.server?.close();
    try {
      if (fs.existsSync(this.socketPath)) fs.unlinkSync(this.socketPath);
    } catch {
      /* ignore */
    }
  }
}
