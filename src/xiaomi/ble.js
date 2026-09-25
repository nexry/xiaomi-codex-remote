import { EventEmitter } from "node:events";

/**
 * Future BLE adapter: discovery, pairing, GATT subscriptions, reconnect, stop.
 * Emit key({key, action}) after decoding confirmed reports; emit disconnect/error.
 * Route voice packets to a separate ATVV session, never to emulator.sendKey().
 */
export class BleSource extends EventEmitter {
  async start() {
    throw new Error("RC003 BLE capture is not implemented; use --xiaomi-source stdin for the MVP.");
  }
  async stop() {}
}
