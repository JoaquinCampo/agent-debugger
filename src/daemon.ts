/** Background daemon — holds the DAP session, accepts CLI commands via Unix socket. */

import { createServer, type Server, type Socket } from "node:net";
import { mkdirSync, writeFileSync, unlinkSync, existsSync } from "node:fs";
import { SESSION_DIR, SOCKET_PATH, PID_FILE } from "./util/paths.js";
import { Session } from "./session.js";
import { Command } from "./protocol.js";

class Daemon {
  private session = new Session();
  private server: Server | null = null;
  private isShuttingDown = false;

  start(): void {
    mkdirSync(SESSION_DIR, { recursive: true });

    // Clean stale socket
    if (existsSync(SOCKET_PATH)) {
      unlinkSync(SOCKET_PATH);
    }

    // Write PID
    writeFileSync(PID_FILE, String(process.pid));

    // Create Unix socket server
    this.server = createServer((conn) => { this.handleConnection(conn); });
    this.server.listen(SOCKET_PATH);

    // Graceful shutdown
    const shutdown = (signal: string) => {
      if (this.isShuttingDown) return;
      this.isShuttingDown = true;
      process.stderr.write(`Daemon received ${signal}, shutting down...\n`);
      this.cleanup();
    };

    process.on("SIGTERM", () => {
      shutdown("SIGTERM");
      // Force exit after 5s if cleanup hangs
      setTimeout(() => process.exit(1), 5_000).unref();
    });
    process.on("SIGINT", () => {
      shutdown("SIGINT");
      setTimeout(() => process.exit(1), 5_000).unref();
    });
    process.on("uncaughtException", (err) => {
      process.stderr.write(`Daemon uncaught exception: ${err.message}\n`);
      shutdown("uncaughtException");
    });
  }

  private handleConnection(conn: Socket): void {
    let data = "";
    let processed = false;

    conn.on("data", (chunk) => {
      if (processed) return;
      data += chunk.toString();

      // Try to parse as JSON (newline-delimited or complete)
      const nlIdx = data.indexOf("\n");
      const toParse = nlIdx !== -1 ? data.substring(0, nlIdx) : data;

      try {
        const cmd = JSON.parse(toParse) as Record<string, unknown>;
        processed = true;
        this.processCommand(cmd, conn);
      } catch {
        // Wait for more data
      }
    });

    conn.on("end", () => {
      if (!processed && data.trim()) {
        try {
          const cmd = JSON.parse(data.trim()) as Record<string, unknown>;
          processed = true;
          this.processCommand(cmd, conn);
        } catch {
          this.sendResponse(conn, { error: "Invalid JSON" });
        }
      }
    });

    conn.on("error", () => {
      // Client disconnected
    });
  }

  private async processCommand(rawCmd: Record<string, unknown>, conn: Socket): Promise<void> {
    try {
      const parsed = Command.safeParse(rawCmd);
      if (!parsed.success) {
        this.sendResponse(conn, { error: `Invalid command: ${parsed.error.message}` });
        return;
      }

      const cmd = parsed.data;

      // Special handling for status command (needs async location)
      let result;
      if (cmd.action === "status") {
        result = await this.session.getStatusAsync();
      } else {
        result = await this.session.handleCommand(cmd);
      }

      this.sendResponse(conn, result as unknown as Record<string, unknown>);

      // Self-terminate on close
      if (cmd.action === "close") {
        setTimeout(() => this.cleanup(), 100);
      }
    } catch (err) {
      this.sendResponse(conn, { error: (err as Error).message });
    }
  }

  private sendResponse(conn: Socket, result: Record<string, unknown>): void {
    try {
      conn.write(JSON.stringify(result) + "\n");
      conn.end();
    } catch {
      // Client may have disconnected
    }
  }

  private cleanup(): void {
    this.session.close().catch(() => {});

    if (this.server) {
      this.server.close();
      this.server = null;
    }

    try { if (existsSync(SOCKET_PATH)) unlinkSync(SOCKET_PATH); } catch { /* ignore */ }
    try { if (existsSync(PID_FILE)) unlinkSync(PID_FILE); } catch { /* ignore */ }

    process.exitCode = 0;
  }
}

// Entry point when run as a separate process
const daemon = new Daemon();
daemon.start();
