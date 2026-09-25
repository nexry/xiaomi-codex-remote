import { EventEmitter } from "node:events";
import net from "node:net";
import fs from "node:fs";

export const DEFAULT_IPC_SOCKET_PATH = "/tmp/xiaomi-remote-events.sock";

/**
 * IpcSource receives pre-parsed {key, action} events from the native Xiaomi Codex Remote GUI
 * or external background process via a Unix Domain Socket.
 *
 * Emits:
 * - "key": { key: string, action: "press" | "release" | "repeat" }
 * - "disconnect": when the client disconnects
 * - "error": on socket errors
 */
export class IpcSource extends EventEmitter {
  constructor({ socketPath = DEFAULT_IPC_SOCKET_PATH } = {}) {
    super();
    this.socketPath = socketPath;
    this.server = null;
    this.activeSocket = null;
    this.buffer = "";
  }

  async start() {
    if (this.server) return;

    // Clean up stale socket file if it exists
    if (fs.existsSync(this.socketPath)) {
      try {
        fs.unlinkSync(this.socketPath);
      } catch {}
    }

    return new Promise((resolve, reject) => {
      const server = net.createServer((socket) => {
        this.activeSocket = socket;
        this.buffer = "";

        socket.on("data", (chunk) => {
          this.buffer += chunk.toString("utf8");
          const lines = this.buffer.split("\n");
          this.buffer = lines.pop() ?? "";

          for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            try {
              const event = JSON.parse(trimmed);
              if (event && typeof event.key === "string" && ["press", "release", "repeat"].includes(event.action)) {
                this.emit("key", { key: event.key, action: event.action });
              }
            } catch (err) {
              // Ignore invalid JSON lines safely
            }
          }
        });

        socket.on("close", () => {
          if (this.activeSocket === socket) {
            this.activeSocket = null;
            this.emit("disconnect");
          }
        });

        socket.on("error", (err) => {
          this.emit("error", err);
        });
      });

      server.on("error", (err) => {
        reject(err);
      });

      server.listen(this.socketPath, () => {
        this.server = server;
        resolve();
      });
    });
  }

  async stop() {
    if (this.activeSocket) {
      this.activeSocket.destroy();
      this.activeSocket = null;
    }
    if (this.server) {
      await new Promise((resolve) => this.server.close(resolve));
      this.server = null;
    }
    if (fs.existsSync(this.socketPath)) {
      try {
        fs.unlinkSync(this.socketPath);
      } catch {}
    }
    this.emit("disconnect");
  }
}
