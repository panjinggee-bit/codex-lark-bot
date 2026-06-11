#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = "https://github.com/panjinggee-bit/codex-lark-bot.git";
const skillRoot = path.join(os.homedir(), ".codex", "skills");
const skillDir = path.join(skillRoot, "codex-lark-bot");
const action = process.argv[2] || "interactive";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    shell: false,
    ...options,
  });

  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

function hasCommand(command) {
  if (process.platform === "win32") {
    return spawnSync("where.exe", [command], {
      stdio: "ignore",
      shell: false,
    }).status === 0;
  }

  return spawnSync("sh", ["-lc", `command -v ${command}`], {
    stdio: "ignore",
    shell: false,
  }).status === 0;
}

if (!hasCommand("git")) {
  console.error("git was not found. Install Git first, then rerun: npx codex-lark-bot");
  process.exit(1);
}

fs.mkdirSync(skillRoot, { recursive: true });

if (fs.existsSync(skillDir)) {
  console.log(`Updating existing skill at ${skillDir}`);
  run("git", ["-C", skillDir, "pull", "--ff-only"]);
} else {
  console.log(`Installing codex-lark-bot skill to ${skillDir}`);
  run("git", ["clone", repo, skillDir]);
}

const bootstrap = path.join(skillDir, "scripts", "codex_lark_bootstrap.ps1");
const mode = action === "bridge" ? "bridge" : "interactive";

const powershellCommand = process.platform === "win32" ? "powershell.exe" : "pwsh";

if (!hasCommand(powershellCommand)) {
  console.error("PowerShell was not found.");
  console.error("Install PowerShell, then run:");
  console.error(`${powershellCommand} -ExecutionPolicy Bypass -File "${bootstrap}" -Mode ${mode}`);
  process.exit(1);
}

console.log("");
if (mode === "bridge") {
  console.log("Starting local Feishu/Lark agent bridge...");
} else {
  console.log("Starting Feishu/Lark agent connection wizard...");
}
run(powershellCommand, ["-ExecutionPolicy", "Bypass", "-File", bootstrap, "-Mode", mode]);
