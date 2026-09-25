// Renders Stream Deck key images: a colored background (agent state color, or a
// light key for actions) with an optional Lucide icon glyph composited on top.
//
// Rasterisation uses `sharp` and the icon SVGs come from `lucide-static` — both
// OPTIONAL dependencies. If either is missing, the renderer degrades gracefully
// to solid color fills, which every Stream Deck can do natively. Rendered key
// images are cached so we only rasterise each (icon, colors, size) once.

let sharp = null;
let lucideDir = null;
let loaded = false;

async function ensureDeps() {
  if (loaded) return;
  loaded = true;
  try {
    ({ default: sharp } = await import("sharp"));
  } catch {
    sharp = null;
  }
  try {
    const mod = await import("lucide-static");
    // lucide-static exposes an icons directory; resolve its path.
    const { fileURLToPath } = await import("node:url");
    const path = await import("node:path");
    const base = path.dirname(fileURLToPath(import.meta.resolve("lucide-static/package.json")));
    lucideDir = path.join(base, "icons");
    void mod;
  } catch {
    lucideDir = null;
  }
}

/** Whether image rendering (icons) is available in this environment. */
export async function canRenderIcons() {
  await ensureDeps();
  return Boolean(sharp && lucideDir);
}

const cache = new Map();

/**
 * Produce a key image buffer (raw RGB) or return null if icons can't be
 * rendered (caller should fall back to a solid color fill).
 *
 * @param {object} spec
 * @param {number} spec.size          key pixel size (square), e.g. 72 or 96
 * @param {{r,g,b}} spec.bg           background color
 * @param {{r,g,b}} [spec.fg]         icon color (default: readable on bg)
 * @param {string|null} [spec.lucide] Lucide icon name, or null for none
 * @param {{r,g,b}} [spec.dot]        optional center dot (agent keys)
 * @returns {Promise<Buffer|null>}
 */
export async function renderKey(spec) {
  await ensureDeps();
  if (!sharp) return null;

  const { size, bg, fg, lucide, dot } = spec;
  const key = JSON.stringify(spec);
  if (cache.has(key)) return cache.get(key);

  const fs = await import("node:fs/promises");
  const layers = [];

  if (lucide && lucideDir) {
    try {
      let svg = await fs.readFile(`${lucideDir}/${lucide}.svg`, "utf8");
      const color = fg ?? readableOn(bg);
      const hex = `#${toHex(color.r)}${toHex(color.g)}${toHex(color.b)}`;
      // Lucide strokes use currentColor; set it explicitly and scale to ~55%.
      svg = svg
        .replace("<svg", `<svg color="${hex}"`)
        .replace(/stroke="[^"]*"/g, `stroke="${hex}"`);
      const glyph = Math.round(size * 0.55);
      const iconPng = await sharp(Buffer.from(svg)).resize(glyph, glyph).png().toBuffer();
      const pad = Math.round((size - glyph) / 2);
      layers.push({ input: iconPng, top: pad, left: pad });
    } catch {
      /* icon missing — background only */
    }
  }

  if (dot) {
    const d = Math.round(size * 0.16);
    const circle = Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${d}" height="${d}">` +
        `<circle cx="${d / 2}" cy="${d / 2}" r="${d / 2}" fill="rgb(${dot.r},${dot.g},${dot.b})"/></svg>`,
    );
    const dotPng = await sharp(circle).png().toBuffer();
    const off = Math.round((size - d) / 2);
    layers.push({ input: dotPng, top: off, left: off });
  }

  const img = sharp({
    create: { width: size, height: size, channels: 3, background: bg },
  });
  if (layers.length) img.composite(layers);

  const buf = await img.removeAlpha().raw().toBuffer();
  cache.set(key, buf);
  return buf;
}

/**
 * Render an LCD dial-zone label: dark background, a centered Lucide icon, and an
 * optional caption underneath. Returns a raw RGB buffer, or null if sharp/lucide
 * aren't available.
 *
 * @param {object} spec
 * @param {number} spec.width
 * @param {number} spec.height
 * @param {string|null} spec.lucide
 * @param {string} [spec.text]
 * @param {{r,g,b}} [spec.bg]
 * @param {{r,g,b}} [spec.fg]
 */
export async function renderLcdZone(spec) {
  await ensureDeps();
  if (!sharp) return null;

  const { width, height, lucide, text = "", bg = { r: 16, g: 16, b: 18 }, fg = { r: 235, g: 235, b: 235 } } = spec;
  const key = "lcd:" + JSON.stringify(spec);
  if (cache.has(key)) return cache.get(key);

  const fs = await import("node:fs/promises");
  const layers = [];
  const glyph = Math.round(Math.min(width, height) * (text ? 0.42 : 0.6));

  if (lucide && lucideDir) {
    try {
      let svg = await fs.readFile(`${lucideDir}/${lucide}.svg`, "utf8");
      const hex = `#${toHex(fg.r)}${toHex(fg.g)}${toHex(fg.b)}`;
      svg = svg.replace("<svg", `<svg color="${hex}"`).replace(/stroke="[^"]*"/g, `stroke="${hex}"`);
      const iconPng = await sharp(Buffer.from(svg)).resize(glyph, glyph).png().toBuffer();
      layers.push({ input: iconPng, top: Math.round(height * 0.14), left: Math.round((width - glyph) / 2) });
    } catch {
      /* icon missing */
    }
  }

  if (text) {
    const fontSize = Math.round(height * 0.2);
    const label = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">` +
      `<text x="50%" y="${height - fontSize / 2}" text-anchor="middle" font-family="sans-serif" ` +
      `font-size="${fontSize}" fill="rgb(${fg.r},${fg.g},${fg.b})">${escapeXml(text)}</text></svg>`;
    layers.push({ input: Buffer.from(label), top: 0, left: 0 });
  }

  const img = sharp({ create: { width, height, channels: 3, background: bg } });
  if (layers.length) img.composite(layers);
  const buf = await img.removeAlpha().raw().toBuffer();
  cache.set(key, buf);
  return buf;
}

function escapeXml(s) {
  return String(s).replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" })[c]);
}

/** Pick black or white for legibility against a background color. */
function readableOn(bg) {
  const luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
  return luma > 140 ? { r: 20, g: 20, b: 20 } : { r: 245, g: 245, b: 245 };
}

function toHex(n) {
  return n.toString(16).padStart(2, "0");
}
