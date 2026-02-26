#!/usr/bin/env node
// cursor-chat-extract.js — Extract structured conversation data from Cursor chat export JSON.
// Usage: ./cursor-chat-extract.js <export.json> [--tools-only]
// Output: Compact JSON summary of messages and tool calls for agent analysis.

const fs = require("fs");
const path = require("path");

const file = process.argv[2];
const toolsOnly = process.argv.includes("--tools-only");

if (!file) {
  console.error("Usage: cursor-chat-extract.js <export.json> [--tools-only]");
  process.exit(1);
}

let data;
try {
  data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
} catch (e) {
  console.error(`Failed to parse ${file}: ${e.message}`);
  process.exit(1);
}

const composerId = Object.keys(data.bubbles || {})[0];
if (!composerId) {
  console.error("No conversation found in export.");
  process.exit(1);
}

const entries = data.bubbles[composerId] || [];

function extractText(val) {
  if (val.text && typeof val.text === "string") return val.text;
  if (!val.richText) return "";
  try {
    const rt = JSON.parse(val.richText);
    return walkLexical(rt.root);
  } catch {
    return "";
  }
}

function walkLexical(node) {
  let out = "";
  if (node.text) out += node.text;
  if (node.children) for (const c of node.children) out += walkLexical(c);
  return out;
}

function parseToolData(raw) {
  if (!raw) return null;
  const d = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (!d.name) return null;

  const result = { name: d.name, status: d.status || "unknown" };

  try {
    const params = JSON.parse(d.params || "{}");
    if (params.command) {
      result.arg = params.command.length > 150
        ? params.command.substring(0, 150) + "..."
        : params.command;
    } else if (params.targetFile) {
      result.arg = params.targetFile;
    } else if (params.globPattern) {
      result.arg = `glob: ${params.globPattern}`;
    } else if (params.pattern) {
      result.arg = `pattern: ${params.pattern}`;
    } else if (params.query) {
      result.arg = `query: ${params.query.substring(0, 100)}`;
    }
  } catch {
    // Ignore parse failures
  }

  return result;
}

function truncate(text, max) {
  if (!text || text.length <= max) return text;
  return text.substring(0, max) + "...";
}

const messages = [];
let totalTools = 0;
let errors = 0;
let cancellations = 0;

for (const entry of entries) {
  let val;
  try {
    val = JSON.parse(entry.value);
  } catch {
    continue;
  }

  const type = val.type === 1 ? "user" : "assistant";
  const text = extractText(val);

  const tool = parseToolData(val.toolFormerData);
  if (tool) {
    totalTools++;
    if (tool.status === "error") errors++;
    if (tool.status === "cancelled") cancellations++;
    messages.push({ type: "tool", ...tool });
    continue;
  }

  if (!text.trim()) continue;

  if (type === "user") {
    messages.push({ type: "user", text: text.trim() });
  } else if (!toolsOnly) {
    messages.push({
      type: "assistant",
      text: truncate(text.trim(), 200),
    });
  }
}

// Detect invoked command from first user message
let invokedCommand = null;
const firstUser = messages.find((m) => m.type === "user");
if (firstUser) {
  const match = firstUser.text.match(/^\/([\w-]+)/);
  if (match) invokedCommand = match[1];
}

const output = {
  invokedCommand,
  stats: {
    messages: messages.filter((m) => m.type === "user").length,
    assistantTurns: messages.filter((m) => m.type === "assistant").length,
    toolCalls: totalTools,
    errors,
    cancellations,
  },
  sequence: messages,
};

console.log(JSON.stringify(output, null, 2));
