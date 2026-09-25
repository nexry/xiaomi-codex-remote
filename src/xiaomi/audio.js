/**
 * Xiaomi RC003 Voice Audio Processing and ADPCM Decoder.
 *
 * Based on Google Voice over BLE (ATVV) specification and Telink TLSR reference implementation:
 * - Audio Codec: IMA-ADPCM 16 kHz, 16-bit Mono.
 * - Packet format: 120 bytes raw ADPCM per BLE packet (or 134 bytes with 6-byte sequence header).
 * - Compression ratio: 4:1 (each byte yields two 16-bit PCM samples).
 */

export const IMA_INDEX_TABLE = Object.freeze([
  -1, -1, -1, -1, 2, 4, 6, 8,
  -1, -1, -1, -1, 2, 4, 6, 8,
]);

export const IMA_STEP_TABLE = Object.freeze([
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
  19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
  50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
  130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
  337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
  876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
  2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
  5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
  15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
]);

export const ATVV_AUDIO_CONSTANTS = Object.freeze({
  SAMPLE_RATE: 16000,
  CHANNELS: 1,
  BITS_PER_SAMPLE: 16,
  RAW_PACKET_LENGTH: 120,
  HEADER_PACKET_LENGTH: 134,
});

/**
 * IMA-ADPCM Decoder for ATVV audio stream.
 */
export class AdpcmDecoder {
  constructor({ sampleRate = 16000, channels = 1 } = {}) {
    this.sampleRate = sampleRate;
    this.channels = channels;
    this.predict = 0;
    this.predictIdx = 0;
  }

  /**
   * Reset the decoder state (must be called at session start or on packet loss).
   */
  reset(predict = 0, predictIdx = 0) {
    this.predict = predict;
    this.predictIdx = Math.max(0, Math.min(88, predictIdx));
  }

  /**
   * Set synchronization parameters (e.g. from ATVV_CHAR_CTL SYNC packet).
   */
  sync(predict, predictIdx) {
    this.predict = predict;
    this.predictIdx = Math.max(0, Math.min(88, predictIdx));
  }

  /**
   * Decodes an ADPCM packet into 16-bit linear PCM samples.
   * @param {Uint8Array} packet
   * @returns {{ samples: Int16Array, sampleRate: number, channels: number }}
   */
  decode(packet) {
    if (!(packet instanceof Uint8Array)) {
      throw new TypeError("Packet must be a Uint8Array");
    }

    let pcode = packet;

    // Check if packet includes 6-byte ATVV header:
    // [seq_hi, seq_lo, stream_id, pred_hi, pred_lo, step_idx]
    if (packet.length >= 6 && packet.length !== ATVV_AUDIO_CONSTANTS.RAW_PACKET_LENGTH) {
      const predRaw = (packet[3] << 8) | packet[4];
      const pred = predRaw >= 0x8000 ? predRaw - 0x10000 : predRaw;
      const idx = packet[5];
      this.sync(pred, idx);
      pcode = packet.subarray(6);
    }

    const sampleCount = pcode.length * 2;
    const samples = new Int16Array(sampleCount);

    let sampleIdx = 0;
    for (let b = 0; b < pcode.length; b++) {
      const byte = pcode[b];
      // In ATVV/Telink: high nibble first, low nibble second (swapped in word)
      const codeSwapped = ((byte >> 4) & 0x0f) | ((byte << 4) & 0xf0);

      let code = codeSwapped;
      for (let n = 0; n < 2; n++) {
        const step = IMA_STEP_TABLE[this.predictIdx];
        let diffq = step >> 3;

        if (code & 4) diffq += step;
        let s = step >> 1;
        if (code & 2) diffq += s;
        s >>= 1;
        if (code & 1) diffq += s;

        if (code & 8) {
          this.predict -= diffq;
        } else {
          this.predict += diffq;
        }

        if (this.predict > 32767) {
          this.predict = 32767;
        } else if (this.predict < -32768) {
          this.predict = -32768;
        }

        this.predictIdx += IMA_INDEX_TABLE[code & 15];
        if (this.predictIdx < 0) {
          this.predictIdx = 0;
        } else if (this.predictIdx > 88) {
          this.predictIdx = 88;
        }

        samples[sampleIdx++] = this.predict;
        code >>= 4;
      }
    }

    return {
      samples,
      sampleRate: this.sampleRate,
      channels: this.channels,
    };
  }
}

/**
 * Creates a standard 44-byte RIFF/WAV header for PCM audio.
 * @param {number} pcmByteLength
 * @param {{ sampleRate?: number, channels?: number, bitsPerSample?: number }} options
 * @returns {Uint8Array}
 */
export function createWavHeader(pcmByteLength, { sampleRate = 16000, channels = 1, bitsPerSample = 16 } = {}) {
  const header = new Uint8Array(44);
  const view = new DataView(header.buffer);

  // RIFF identifier
  header.set([0x52, 0x49, 0x46, 0x46], 0); // "RIFF"
  // File size - 8
  view.setUint32(4, 36 + pcmByteLength, true);
  // WAVE identifier
  header.set([0x57, 0x41, 0x56, 0x45], 8); // "WAVE"
  // fmt subchunk
  header.set([0x66, 0x6d, 0x74, 0x20], 12); // "fmt "
  view.setUint32(16, 16, true); // Subchunk1Size (16 for PCM)
  view.setUint16(20, 1, true); // AudioFormat (1 = PCM)
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * channels * (bitsPerSample / 8), true); // ByteRate
  view.setUint16(32, channels * (bitsPerSample / 8), true); // BlockAlign
  view.setUint16(34, bitsPerSample, true);
  // data subchunk
  header.set([0x64, 0x61, 0x74, 0x61], 36); // "data"
  view.setUint32(40, pcmByteLength, true);

  return header;
}
