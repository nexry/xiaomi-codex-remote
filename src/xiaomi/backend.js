import { EventEmitter } from "node:events";
import { Act } from "../protocol.js";
import { createMapping, resolveKey } from "./mapping.js";

/**
 * source: EventEmitter with start()/stop(); emits key({key, action}), disconnect,
 * end, error(Error). action is press|release|repeat. No source = injected events.
 * This layer never decodes raw HID/BLE reports or transports microphone audio.
 */
export class XiaomiRemoteBackend extends EventEmitter {
  constructor(emulator, { source = null, mapping = {} } = {}) {
    super();
    this.emulator = emulator;
    this.source = source;
    this.mapping = createMapping(mapping);
    this.running = false;
    this.pressed = new Map();
    this.handlers = {
      key: (event) => this.handleEvent(event),
      disconnect: () => this.releaseAll(),
      end: () => { this.releaseAll(); this.emit("end"); },
      error: (error) => { this.releaseAll(); this.emit("error", error); },
    };
  }

  async start() {
    if (this.running) return;
    this.running = true;
    for (const [name, handler] of Object.entries(this.handlers)) this.source?.on(name, handler);
    try {
      await this.source?.start();
    } catch (error) {
      await this.stop().catch(() => {});
      throw error;
    }
  }

  handleEvent(event) {
    if (!this.running || !event || !["press", "release", "repeat"].includes(event.action)) return false;
    const binding = resolveKey(event.key, this.mapping);
    if (!binding) return false;
    const held = this.pressed.has(event.key);
    if (event.action === "release") {
      if (!held) return false;
      this.pressed.delete(event.key);
      if (binding.kind === "key") this.emulator.sendKey(binding.keycode, Act.RELEASE, binding.agent);
      else if (binding.kind === "joystick") this.emulator.sendJoystick(binding.angle, 0);
    } else if (event.action === "press") {
      if (held) return false;
      this.pressed.set(event.key, binding);
      if (binding.kind === "joystick") this.emulator.sendJoystick(binding.angle, 1.0);
      else this.emulator.sendKey(binding.keycode, binding.kind === "rotate" ? Act.ROTATE : Act.PRESS, binding.agent);
    } else {
      if (!held) return false;
      if (binding.kind === "joystick") this.emulator.sendJoystick(binding.angle, 1.0);
      else if (binding.kind === "rotate") this.emulator.sendKey(binding.keycode, Act.ROTATE, binding.agent);
      else return false;
    }
    return true;
  }

  releaseAll() {
    for (const binding of this.pressed.values()) {
      if (binding.kind === "key") this.emulator.sendKey(binding.keycode, Act.RELEASE, binding.agent);
      else if (binding.kind === "joystick") this.emulator.sendJoystick(binding.angle, 0);
    }
    this.pressed.clear();
  }

  async stop() {
    if (!this.running) return;
    this.running = false;
    this.releaseAll();
    for (const [name, handler] of Object.entries(this.handlers)) this.source?.off(name, handler);
    await this.source?.stop?.();
  }
}
