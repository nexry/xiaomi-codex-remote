import { EventEmitter } from "node:events";
import { createInterface } from "node:readline";

/** Development input only: one {key, action} JSON object per line. EOF emits end. */
export class StdinSource extends EventEmitter {
  constructor(stream = process.stdin) {
    super();
    this.stream = stream;
    this.reader = null;
    this.onError = (error) => this.emit("error", error);
    this.onEnd = () => this.emit("end");
  }
  async start() {
    if (this.reader) return;
    this.stream.on("error", this.onError);
    this.reader = createInterface({ input: this.stream, terminal: false, crlfDelay: Infinity });
    this.reader.on("line", (line) => {
      if (!line.trim()) return;
      let event;
      try { event = JSON.parse(line); }
      catch { this.emit("error", new Error("Xiaomi stdin expects one JSON {key, action} object per line.")); return; }
      if (!event || typeof event.key !== "string" || !["press", "release", "repeat"].includes(event.action)) {
        this.emit("error", new Error("Xiaomi JSON event requires key:string and action:press|release|repeat."));
        return;
      }
      this.emit("key", event);
    });
    this.reader.on("close", this.onEnd);
  }
  async stop() {
    this.reader?.off("close", this.onEnd);
    this.reader?.close();
    this.reader?.removeAllListeners();
    this.reader = null;
    this.stream.off("error", this.onError);
    this.stream.pause();
  }
}
