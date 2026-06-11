#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = "https://github.com/panjinggee-bit/codex-lark-bot.git";
const skillRoot = path.join(os.homedir(), ".codex", "skills");
const skillDir = path.join(skillRoot, "codex-lark-bot");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    shell: process.platform === "win32",
    ...options,
  });

  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

function hasCommand(command) {
  const probe = process.platform === "win32" ? "where" : "command";
  const args = process.platform === "win32" ? [command] : ["-v", command];
  return spawnSync(probe, args, {
    stdio: "ignore",
    shell: process.platform === "win32",
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

if (process.platform !== "win32") {
  console.error("The interactive wizard currently requires PowerShell. Install PowerShell, then run:");
  console.error(`pwsh -ExecutionPolicy Bypass -File "${bootstrap}" -Mode interactive`);
  process.exit(1);
}

console.log("");
console.log("Starting Feishu/Lark agent connection wizard...");
run("powershell", ["-ExecutionPolicy", "Bypass", "-File", bootstrap, "-Mode", "interactive"]);
