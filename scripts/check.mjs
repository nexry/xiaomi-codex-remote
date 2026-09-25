// Syntax validation without adding a lint dependency.
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
function check(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const file = join(dir, entry.name);
    if (entry.isDirectory()) check(file);
    else if (/\.(?:mjs|cjs|js)$/.test(file)) {
      const result = spawnSync(process.execPath, ["--check", file], { stdio: "inherit" });
      if (result.error) throw result.error;
      if (result.status !== 0) process.exit(result.status || 1);
    }
  }
}
for (const dir of ["bin", "src", "shim", "scripts", "test"]) check(dir);
console.log("JavaScript syntax checks passed.");
