// Preload entry point for the node-hid shim.
//
// Injected into the ChatGPT app's main process via:
//   NODE_OPTIONS="--require /abs/path/to/shim/preload.cjs"
//
// It installs the require hook (see patch.cjs) so the app enumerates and opens
// the virtual Codex Micro, bridged over a Unix socket to the external emulator.
// Set CODEX_MICRO_SOCKET to match the bridge's --socket, and optionally
// CODEX_MICRO_SHIM_LOG to a writable file for diagnostics.

const { installHook, defaultSocketPath } = require("./patch.cjs");

try {
  const socketPath = defaultSocketPath();
  installHook({ socketPath });
} catch (err) {
  // Never take the host app down if the shim fails to install.
  try {
    process.stderr.write(`[codex-micro-shim] install failed: ${err && err.stack}\n`);
  } catch {
    /* ignore */
  }
}
