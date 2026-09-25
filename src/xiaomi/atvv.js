import { EventEmitter } from "node:events";

/**
 * Google Voice over BLE (ATVV) Service & Protocol Constants.
 * Verified from Xiaomi RC003 captures and Telink RCU specifications.
 */
export const ATVV_UUIDS = Object.freeze({
  SERVICE: "AB5E0001-5A21-4F05-BC7D-AF01F617B664",
  TX: "AB5E0002-5A21-4F05-BC7D-AF01F617B664",
  RX: "AB5E0003-5A21-4F05-BC7D-AF01F617B664",
  CTL: "AB5E0004-5A21-4F05-BC7D-AF01F617B664",
});

export const ATVV_COMMANDS = Object.freeze({
  GET_CAPS: 0x0a,
  MIC_OPEN: 0x0c,
  MIC_CLOSE: 0x0d,
  EXTEND: 0x0e,
});

export const ATVV_CTL_OPCODES = Object.freeze({
  AUDIO_STOP: 0x00,
  AUDIO_START: 0x04,
  DPAD_SELECT: 0x07,
  SEARCH: 0x08,
  SYNC: 0x0a,
  CAPS_RESP: 0x0b,
  MIC_OPEN_ERROR: 0x0c,
});

export const ATVV_CODECS = Object.freeze({
  ADPCM_8K: 0x0001,
  ADPCM_16K: 0x0002,
});

export const ATVV_STOP_REASONS = Object.freeze({
  MIC_CLOSE: 0x00,
  RELEASE_HTT: 0x02,
  UPCOMING_START: 0x04,
  TIMEOUT: 0x08,
  DISABLE_CCC: 0x10,
  OTHER: 0x80,
});

/**
 * Session state machine for ATVV voice protocol.
 */
export class AtvvSession extends EventEmitter {
  constructor({ writeControl = null, onEncodedAudio = null, onError = null } = {}) {
    super();
    this.writeControl = writeControl;
    this.onEncodedAudio = onEncodedAudio;
    this.onError = onError;

    this.active = false;
    this.micOpen = false;
    this.caps = null;
    this.streamId = 0;
  }

  /**
   * Start an ATVV session and negotiate capabilities with the remote.
   */
  async start({ writeControl = this.writeControl, onEncodedAudio = this.onEncodedAudio, onError = this.onError } = {}) {
    if (this.active) return;
    this.writeControl = writeControl;
    this.onEncodedAudio = onEncodedAudio;
    this.onError = onError;
    this.active = true;
    this.micOpen = false;

    // Send GET_CAPS for v0.4 / v1.0
    await this.sendGetCaps();
  }

  async sendGetCaps(versionMajor = 0x00, versionMinor = 0x04) {
    if (!this.writeControl) return;
    const packet = new Uint8Array([ATVV_COMMANDS.GET_CAPS, versionMajor, versionMinor]);
    await this.writeControl(packet);
  }

  /**
   * Send MIC_OPEN to remote to start voice streaming.
   */
  async openMic(codec = ATVV_CODECS.ADPCM_16K) {
    if (!this.active || !this.writeControl) return;
    this.micOpen = true;
    const packet = new Uint8Array([
      ATVV_COMMANDS.MIC_OPEN,
      (codec >> 8) & 0xff,
      codec & 0xff,
    ]);
    await this.writeControl(packet);
  }

  /**
   * Send MIC_CLOSE to remote to stop voice streaming.
   */
  async closeMic() {
    if (!this.active || !this.writeControl) return;
    this.micOpen = false;
    const packet = new Uint8Array([ATVV_COMMANDS.MIC_CLOSE]);
    await this.writeControl(packet);
  }

  /**
   * Process a control packet received from ATVV_CHAR_CTL notification.
   * @param {Uint8Array} packet
   */
  pushControl(packet) {
    if (!(packet instanceof Uint8Array) || packet.length === 0) return;
    const opcode = packet[0];

    switch (opcode) {
      case ATVV_CTL_OPCODES.CAPS_RESP: {
        if (packet.length >= 7) {
          const major = packet[1];
          const minor = packet[2];
          const codecs = (packet[3] << 8) | packet[4];
          const frameLen = packet.length >= 7 ? (packet[5] << 8) | packet[6] : 134;
          this.caps = { version: `${major}.${minor}`, codecs, frameLen };
          this.emit("caps", this.caps);
        }
        break;
      }

      case ATVV_CTL_OPCODES.AUDIO_START: {
        const reason = packet.length > 1 ? packet[1] : 0;
        const codec = packet.length > 2 ? packet[2] : ATVV_CODECS.ADPCM_16K;
        const streamId = packet.length > 3 ? packet[3] : 0;
        this.streamId = streamId;
        this.emit("audio_start", { reason, codec, streamId });
        break;
      }

      case ATVV_CTL_OPCODES.AUDIO_STOP: {
        const reason = packet.length > 1 ? packet[1] : 0;
        this.micOpen = false;
        this.emit("audio_stop", { reason });
        break;
      }

      case ATVV_CTL_OPCODES.SYNC: {
        if (packet.length >= 7) {
          const sampleRateCode = packet[1];
          const seqNo = (packet[2] << 8) | packet[3];
          const predRaw = (packet[4] << 8) | packet[5];
          const predict = predRaw >= 0x8000 ? predRaw - 0x10000 : predRaw;
          const predictIdx = packet[6];
          this.emit("sync", { sampleRateCode, seqNo, predict, predictIdx });
        }
        break;
      }

      case ATVV_CTL_OPCODES.SEARCH: {
        this.emit("search");
        break;
      }

      case ATVV_CTL_OPCODES.MIC_OPEN_ERROR: {
        const errCode = packet.length >= 3 ? (packet[1] << 8) | packet[2] : 0;
        const err = new Error(`ATVV MIC_OPEN error: 0x${errCode.toString(16)}`);
        this.onError?.(err);
        this.emit("error", err);
        break;
      }

      default:
        break;
    }
  }

  /**
   * Process an audio packet received from ATVV_CHAR_RX notification.
   * @param {Uint8Array} packet
   */
  pushAudio(packet) {
    if (!this.active || !(packet instanceof Uint8Array)) return;
    this.onEncodedAudio?.(packet);
    this.emit("audio", packet);
  }

  /**
   * Stop session and release all resources.
   */
  async stop() {
    if (!this.active) return;
    this.active = false;
    if (this.micOpen) {
      await this.closeMic().catch(() => {});
    }
    this.emit("stop");
    this.removeAllListeners();
  }
}
