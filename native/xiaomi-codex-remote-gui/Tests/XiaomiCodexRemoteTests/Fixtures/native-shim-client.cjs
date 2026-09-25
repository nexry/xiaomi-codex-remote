const assert = require("node:assert/strict");
const { pathToFileURL } = require("node:url");
const [root, socketPath] = process.argv.slice(2);
const timer = setTimeout(() => { console.error("shim test timed out"); process.exit(1); }, 4000);
(async () => {
  const { encode, Reassembler } = await import(pathToFileURL(root + "/src/framing.js"));
  const shim = require(root + "/shim/patch.cjs");
  const patched = shim.patchModule({ devices: () => [], HIDAsync: { open: async () => {} } }, { socketPath });
  const device = patched.devices().find(d => d.vendorId === 0x303a && d.productId === 0x8360);
  assert.equal(device.usagePage, 0xff00);
  const dev = await patched.HIDAsync.open(device.path);
  while (!dev.connected) await new Promise(resolve => setTimeout(resolve, 5));
  const reassembler = new Reassembler();
  const response = new Promise((resolve, reject) => {
    dev.on("error", reject);
    dev.on("data", frame => {
      for (const { message } of reassembler.push(frame)) resolve(JSON.parse(message));
    });
  });
  for (const frame of encode('{"id":1,"method":"device.status"}')) await dev.write(frame);
  assert.deepEqual(await response, {
    id: 1, result: { version: "1.0.0", profile_index: 0, layer_index: 0, battery: 100, is_charging: false }
  });
  await dev.close();
  clearTimeout(timer);
})().catch(error => { console.error(error); process.exit(1); });
