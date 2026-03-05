#!/usr/bin/env node
import { createServer } from "node:http";
import { readdir, stat, open, readFile, writeFile, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { spawn } from "node:child_process";

const PID_FILE = join(homedir(), ".claude-peak-server.pid");
const PORT = parseInt(process.env.PORT || "3200", 10);
const CLAUDE_DIR = join(homedir(), ".claude", "projects");

// Update notifier
const require = createRequire(import.meta.url);
const pkg = require("../package.json");
import("update-notifier").then(({ default: updateNotifier }) => {
  updateNotifier({ pkg, updateCheckInterval: 1000 * 60 * 60 * 24 }).notify();
}).catch(() => {});

// --- Colors ---

const tty = process.stdout.isTTY !== false;
const c = (code: string) => (tty ? code : "");
const GREEN = c("\x1b[32m");
const RED = c("\x1b[31m");
const DIM = c("\x1b[2m");
const BOLD = c("\x1b[1m");
const NC = c("\x1b[0m");

// --- CLI commands ---

const cmd = process.argv[2];

if (cmd === "down") {
  try {
    const pid = parseInt(await readFile(PID_FILE, "utf8"), 10);
    process.kill(pid);
    await unlink(PID_FILE);
    console.log(`💀 Flame out. ${DIM}(pid ${pid})${NC}`);
  } catch {
    console.log(`💀 Nothing to kill.`);
  }
  process.exit(0);
}

if (cmd === "status") {
  try {
    const pid = parseInt(await readFile(PID_FILE, "utf8"), 10);
    process.kill(pid, 0);
    console.log(`🔥 ALIVE AND BURNING :${BOLD}${PORT}${NC} ${DIM}(pid ${pid})${NC}`);
  } catch {
    console.log(`💀 Dead. Light it up. If you can.`);
  }
  process.exit(0);
}

if (cmd === "fg") {
  startServer();
} else {
  try {
    const pid = parseInt(await readFile(PID_FILE, "utf8"), 10);
    process.kill(pid, 0);
    console.log(`🔥 Already riding on :${BOLD}${PORT}${NC} ${DIM}(pid ${pid})${NC}`);
    process.exit(0);
  } catch {}

  const child = spawn(process.argv[0], [...process.argv.slice(1), "fg"], {
    detached: true,
    stdio: "ignore",
    env: { ...process.env, PORT: String(PORT) },
  });
  child.unref();
  await writeFile(PID_FILE, String(child.pid));
  console.log(`😏 Light it up. If you can. :${BOLD}${PORT}${NC} ${DIM}(pid ${child.pid})${NC}`);
  process.exit(0);
}

// --- Server ---

function startServer() {
  const fileOffsets = new Map<string, number>();
  let recentTokens: { date: number; tokens: number }[] = [];

  async function findJsonlFiles(dir: string): Promise<string[]> {
    const results: string[] = [];
    try {
      const entries = await readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
          results.push(...(await findJsonlFiles(full)));
        } else if (entry.name.endsWith(".jsonl")) {
          const s = await stat(full);
          if (Date.now() - s.mtimeMs < 60_000) results.push(full);
        }
      }
    } catch {}
    return results;
  }

  async function readNewLines(filePath: string) {
    try {
      const s = await stat(filePath);
      const lastOffset = fileOffsets.get(filePath) ?? s.size;
      if (s.size <= lastOffset) {
        fileOffsets.set(filePath, s.size);
        return;
      }
      const fh = await open(filePath, "r");
      const buf = Buffer.alloc(s.size - lastOffset);
      await fh.read(buf, 0, buf.length, lastOffset);
      await fh.close();
      fileOffsets.set(filePath, s.size);

      const now = Date.now();
      for (const line of buf.toString("utf8").split("\n")) {
        if (!line.trim()) continue;
        try {
          const json = JSON.parse(line);
          const usage = json?.message?.usage;
          if (!usage) continue;
          const total =
            (usage.input_tokens || 0) +
            (usage.output_tokens || 0) +
            (usage.cache_read_input_tokens || 0) +
            (usage.cache_creation_input_tokens || 0);
          if (total > 0) recentTokens.push({ date: now, tokens: total });
        } catch {}
      }
    } catch {}
  }

  async function scan() {
    const files = await findJsonlFiles(CLAUDE_DIR);
    await Promise.all(files.map(readNewLines));
    const cutoff = Date.now() - 30_000;
    recentTokens = recentTokens.filter((t) => t.date >= cutoff);
  }

  setInterval(scan, 2000);
  scan();

  // Clean up PID file on exit
  const cleanup = async () => { try { await unlink(PID_FILE); } catch {} process.exit(); };
  process.on("SIGTERM", cleanup);
  process.on("SIGINT", cleanup);

  const server = createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");

    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
      return;
    }

    if (req.url === "/api/activity") {
      const totalTokens = recentTokens.reduce((s, t) => s + t.tokens, 0);
      const tokensPerSecond = totalTokens / 30;
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          tokensPerSecond,
          recentTokens: recentTokens.map((t) => ({
            date: new Date(t.date).toISOString(),
            tokens: t.tokens,
          })),
        })
      );
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  });

  server.listen(PORT, "0.0.0.0", () => {
    writeFile(PID_FILE, String(process.pid)).catch(() => {});
  });
}
