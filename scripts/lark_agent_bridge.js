#!/usr/bin/env node

const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");

const agent = process.argv.includes("--agent")
  ? process.argv[process.argv.indexOf("--agent") + 1]
  : "claude";
const maxReplyChars = process.argv.includes("--max-reply-chars")
  ? Number(process.argv[process.argv.indexOf("--max-reply-chars") + 1])
  : 3500;

const systemContext = `You are replying to a Feishu/Lark user message through a local bridge.
Keep the reply concise and useful.
Do not modify local files or run risky actions from this bridge response.
If the user asks for a risky local action, ask them to confirm in their local agent session instead.`;

const seenQueue = [];
const seenSet = new Set();

function info(message) {
  console.log(`[bridge] ${message}`);
}

function error(message) {
  console.error(`[bridge:error] ${message}`);
}

function commandExists(command) {
  const probe = process.platform === "win32" ? "where.exe" : "sh";
  const args = process.platform === "win32" ? [command] : ["-lc", `command -v ${command}`];
  return spawnSync(probe, args, { stdio: "ignore" }).status === 0;
}

function addSeen(messageId) {
  if (!messageId || seenSet.has(messageId)) return false;
  seenSet.add(messageId);
  seenQueue.push(messageId);
  while (seenQueue.length > 200) {
    seenSet.delete(seenQueue.shift());
  }
  return true;
}

function firstValueByName(node, names) {
  if (node == null) return undefined;
  if (typeof node !== "object") return undefined;

  if (Array.isArray(node)) {
    for (const item of node) {
      const value = firstValueByName(item, names);
      if (value != null) return value;
    }
    return undefined;
  }

  for (const name of names) {
    if (Object.prototype.hasOwnProperty.call(node, name) && node[name] != null) {
      return node[name];
    }
  }

  for (const value of Object.values(node)) {
    const found = firstValueByName(value, names);
    if (found != null) return found;
  }
  return undefined;
}

function convertMessageText(raw) {
  if (raw == null) return "";
  const text = String(raw).trim();
  if (!text) return "";
  if (text.startsWith("{")) {
    try {
      const content = JSON.parse(text);
      const nested = firstValueByName(content, ["text", "content"]);
      if (nested != null) return String(nested).trim();
    } catch {
      return text;
    }
  }
  return text;
}

function getMessage(event) {
  const messageId = firstValueByName(event, ["message_id", "messageId", "id"]);
  const rawText = firstValueByName(event, ["text", "content"]);
  const chatType = firstValueByName(event, ["chat_type", "chatType"]);
  const senderType = firstValueByName(event, ["sender_type", "senderType"]);
  const messageType = firstValueByName(event, ["message_type", "messageType", "msg_type", "msgType"]);
  return {
    messageId: messageId ? String(messageId) : "",
    text: convertMessageText(rawText),
    chatType: chatType ? String(chatType) : "",
    senderType: senderType ? String(senderType) : "",
    messageType: messageType ? String(messageType) : "",
  };
}

function shouldHandle(message) {
  if (!message.messageId || !message.text) return false;
  if (/bot/i.test(message.senderType)) return false;
  if (message.messageType && !/text|post/i.test(message.messageType)) return false;
  return true;
}

function truncate(text, limit) {
  return text.length <= limit ? text : `${text.slice(0, limit)}\n\n[reply truncated; ask the bot to continue]`;
}

function runCapture(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
    ...options,
  });
  if (result.status !== 0) {
    throw new Error(`${command} failed with exit code ${result.status}: ${result.stderr || result.stdout}`);
  }
  return (result.stdout || "").trim();
}

function invokeClaude(prompt) {
  return runCapture("claude", ["--print", "--permission-mode", "plan", prompt]);
}

function invokeCodex(prompt) {
  const promptPath = path.join(os.tmpdir(), `codex-lark-prompt-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`);
  fs.writeFileSync(promptPath, prompt, "utf8");
  try {
    const ps = process.platform === "win32" ? "powershell.exe" : "pwsh";
    const escaped = promptPath.replace(/'/g, "''");
    return runCapture(ps, [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      `Get-Content -Raw -Encoding UTF8 -LiteralPath '${escaped}' | codex exec --skip-git-repo-check -`,
    ], { cwd: os.homedir() });
  } finally {
    fs.rmSync(promptPath, { force: true });
  }
}

function invokeAgent(userText) {
  const prompt = `${systemContext}\n\nUser message:\n${userText}`;
  return agent === "codex" ? invokeCodex(prompt) : invokeClaude(prompt);
}

function replyToMessage(messageId, replyText) {
  runCapture("lark-cli", [
    "im",
    "+messages-reply",
    "--as",
    "bot",
    "--message-id",
    messageId,
    "--text",
    truncate(replyText, maxReplyChars),
  ]);
}

if (!["claude", "codex"].includes(agent)) {
  error(`Unsupported agent: ${agent}`);
  process.exit(1);
}
for (const command of ["lark-cli", agent]) {
  if (!commandExists(command)) {
    error(`${command} was not found on PATH.`);
    process.exit(1);
  }
}

info(`Starting local Feishu/Lark bridge with agent: ${agent}`);
info("Only text events from im.message.receive_v1 are handled. Press Ctrl+C to stop.");

const subscriber = spawn("lark-cli", [
  "event",
  "+subscribe",
  "--event-types",
  "im.message.receive_v1",
  "--quiet",
], {
  stdio: ["ignore", "pipe", "pipe"],
  env: { ...process.env, PYTHONIOENCODING: "utf-8" },
});

subscriber.stderr.setEncoding("utf8");
subscriber.stderr.on("data", (chunk) => {
  const text = chunk.toString().trim();
  if (text) error(text);
});

const rl = readline.createInterface({
  input: subscriber.stdout.setEncoding("utf8"),
  crlfDelay: Infinity,
});

info("Listening for Feishu/Lark messages...");

rl.on("line", (line) => {
  if (!line.trim()) return;

  let event;
  try {
    event = JSON.parse(line);
  } catch (err) {
    error(`Could not parse event JSON: ${err.message}`);
    return;
  }

  const message = getMessage(event);
  if (!shouldHandle(message)) return;
  if (!addSeen(message.messageId)) return;

  info(`Received message ${message.messageId}: ${message.text}`);

  let reply;
  try {
    reply = invokeAgent(message.text) || "Agent returned an empty response.";
  } catch (err) {
    error(err.message);
    reply = `Local ${agent} failed to answer. Check the bridge terminal for details: ${err.message}`;
  }

  try {
    replyToMessage(message.messageId, reply);
    info(`Replied to ${message.messageId}`);
  } catch (err) {
    error(err.message);
  }
});

subscriber.on("exit", (code) => {
  process.exit(code ?? 0);
});
