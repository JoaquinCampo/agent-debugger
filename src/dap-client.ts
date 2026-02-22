/** DAP (Debug Adapter Protocol) client over TCP.*/

import { Socket } from "node:net";
import { EventEmitter } from "node:events";
import type { DAPResponse, DAPEvent } from "./dap-types.js";

interface PendingRequest {
  resolve: (resp: DAPResponse) => void;
  reject: (err: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class DAPClient extends EventEmitter {
  private sock: Socket | null = null;
  private seq = 0;
  private pending = new Map<number, PendingRequest>();
  /** Deferred promises for requestAsync — survives dispatch resolution. */
  private asyncResponses = new Map<number, Deferred<DAPResponse>>();
  private eventQueue: DAPEvent[] = [];
  private buffer = Buffer.alloc(0);
  private capabilities: Record<string, unknown> = {};

  /** Connect to a DAP server with retry loop. */
  async connect(host: string, port: number, timeout = 10000): Promise<void> {
    const deadline = Date.now() + timeout;
    let lastErr: Error | null = null;

    while (Date.now() < deadline) {
      try {
        await this.tryConnect(host, port, Math.min(1000, deadline - Date.now()));
        return;
      } catch (err) {
        lastErr = err as Error;
        await sleep(100);
      }
    }
    throw new Error(`Could not connect to ${host}:${port} within ${timeout}ms: ${lastErr?.message}`);
  }

  private tryConnect(host: string, port: number, timeout: number): Promise<void> {
    return new Promise((resolve, reject) => {
      const sock = new Socket();
      const timer = setTimeout(() => {
        sock.destroy();
        reject(new Error("Connection timeout"));
      }, timeout);

      sock.once("connect", () => {
        clearTimeout(timer);
        this.sock = sock;
        this.setupSocket();
        resolve();
      });

      sock.once("error", (err) => {
        clearTimeout(timer);
        sock.destroy();
        reject(err);
      });

      sock.connect(port, host);
    });
  }

  private setupSocket(): void {
    if (!this.sock) return;

    this.sock.on("data", (chunk) => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      this.processBuffer();
    });

    this.sock.on("close", () => {
      for (const [seq, pending] of this.pending) {
        clearTimeout(pending.timer);
        pending.reject(new Error("Connection closed"));
        this.pending.delete(seq);
      }
      // Also reject any async deferred that hasn't resolved
      for (const [seq, deferred] of this.asyncResponses) {
        if (!deferred.settled) {
          deferred.reject(new Error("Connection closed"));
        }
        this.asyncResponses.delete(seq);
      }
    });

    this.sock.on("error", () => {
      // Handled by close
    });
  }

  private processBuffer(): void {
    while (true) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) return;

      const header = this.buffer.subarray(0, headerEnd).toString("ascii");
      let contentLength: number | null = null;
      for (const line of header.split("\r\n")) {
        if (line.toLowerCase().startsWith("content-length:")) {
          contentLength = parseInt(line.split(":")[1]!.trim(), 10);
        }
      }
      if (contentLength === null) return;

      const bodyStart = headerEnd + 4;
      const bodyEnd = bodyStart + contentLength;
      if (this.buffer.length < bodyEnd) return;

      const body = this.buffer.subarray(bodyStart, bodyEnd).toString("utf-8");
      this.buffer = this.buffer.subarray(bodyEnd);

      const msg = JSON.parse(body);
      this.dispatch(msg);
    }
  }

  private dispatch(msg: { type: string; [key: string]: unknown }): void {
    if (msg.type === "response") {
      const resp = msg as unknown as DAPResponse;

      // Check async responses first (requestAsync + waitForResponse)
      const deferred = this.asyncResponses.get(resp.request_seq);
      if (deferred) {
        deferred.resolve(resp);
        // Don't delete — waitForResponse may not have been called yet.
        // It gets cleaned up there.
      }

      // Also resolve any pending entry (from request())
      const pending = this.pending.get(resp.request_seq);
      if (pending) {
        clearTimeout(pending.timer);
        this.pending.delete(resp.request_seq);
        pending.resolve(resp);
      }
    } else if (msg.type === "event") {
      const evt = msg as unknown as DAPEvent;
      this.eventQueue.push(evt);
      this.emit("event", evt);
      this.emit(`event:${evt.event}`, evt);
    }
  }

  private send(msg: Record<string, unknown>): void {
    if (!this.sock) throw new Error("Not connected");
    const body = Buffer.from(JSON.stringify(msg), "utf-8");
    const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
    this.sock.write(Buffer.concat([header, body]));
  }

  /** Send a request and wait for the response. */
  request(command: string, args?: Record<string, unknown>, timeout = 30000): Promise<DAPResponse> {
    return new Promise((resolve, reject) => {
      this.seq++;
      const seq = this.seq;

      const timer = setTimeout(() => {
        this.pending.delete(seq);
        reject(new Error(`DAP request '${command}' timed out after ${timeout}ms`));
      }, timeout);

      this.pending.set(seq, { resolve, reject, timer });

      const msg: Record<string, unknown> = { seq, type: "request", command };
      if (args) msg.arguments = args;
      this.send(msg);
    });
  }

  /** Send a request without waiting. Returns the seq for later retrieval via waitForResponse. */
  requestAsync(command: string, args?: Record<string, unknown>): number {
    this.seq++;
    const seq = this.seq;
    const msg: Record<string, unknown> = { seq, type: "request", command };
    if (args) msg.arguments = args;

    // Create a deferred that survives dispatch resolution
    const deferred = createDeferred<DAPResponse>();
    this.asyncResponses.set(seq, deferred);

    this.send(msg);
    return seq;
  }

  /** Wait for response to a previously sent async request. */
  async waitForResponse(seq: number, timeout = 30000): Promise<DAPResponse> {
    const deferred = this.asyncResponses.get(seq);
    if (!deferred) {
      throw new Error(`No pending async request with seq ${seq}`);
    }

    // Race the deferred promise against a timeout
    const result = await Promise.race([
      deferred.promise,
      new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error(`DAP request seq=${seq} timed out after ${timeout}ms`)), timeout);
      }),
    ]);

    // Clean up
    this.asyncResponses.delete(seq);
    return result;
  }

  /** Wait for a specific DAP event. */
  waitForEvent(eventName: string, timeout = 30000): Promise<DAPEvent | null> {
    // Check queue first
    const idx = this.eventQueue.findIndex((e) => e.event === eventName);
    if (idx !== -1) {
      return Promise.resolve(this.eventQueue.splice(idx, 1)[0]!);
    }

    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.removeListener(`event:${eventName}`, handler);
        resolve(null);
      }, timeout);

      const handler = (evt: DAPEvent) => {
        clearTimeout(timer);
        this.removeListener(`event:${eventName}`, handler);
        // Remove from queue if it was also queued
        const qi = this.eventQueue.indexOf(evt);
        if (qi !== -1) this.eventQueue.splice(qi, 1);
        resolve(evt);
      };

      this.once(`event:${eventName}`, handler);
    });
  }

  /** Drain all events of a given type from the queue. */
  drainEvents(eventName?: string): DAPEvent[] {
    if (eventName) {
      const matched = this.eventQueue.filter((e) => e.event === eventName);
      this.eventQueue = this.eventQueue.filter((e) => e.event !== eventName);
      return matched;
    }
    const all = [...this.eventQueue];
    this.eventQueue = [];
    return all;
  }

  getCapabilities(): Record<string, unknown> {
    return this.capabilities;
  }

  /** Disconnect from the DAP server. */
  async disconnect(terminate = true): Promise<void> {
    try {
      await this.request("disconnect", { restart: false, terminateDebuggee: terminate }, 5000);
    } catch {
      // Best effort
    } finally {
      if (this.sock) {
        this.sock.destroy();
        this.sock = null;
      }
      for (const [, pending] of this.pending) {
        clearTimeout(pending.timer);
      }
      this.pending.clear();
      this.asyncResponses.clear();
    }
  }

  async close(): Promise<void> {
    await this.disconnect(true);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

interface Deferred<T> {
  resolve: (value: T) => void;
  reject: (err: Error) => void;
  promise: Promise<T>;
  settled: boolean;
}

function createDeferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  let reject!: (err: Error) => void;
  const deferred: Deferred<T> = {
    settled: false,
  } as Deferred<T>;

  deferred.promise = new Promise<T>((res, rej) => {
    resolve = (val) => { deferred.settled = true; res(val); };
    reject = (err) => { deferred.settled = true; rej(err); };
  });
  deferred.resolve = resolve;
  deferred.reject = reject;

  return deferred;
}
