import test from "node:test";
import assert from "node:assert/strict";
import { Command } from "../src/protocol.js";
import { Session } from "../src/session.js";

test("Command.parse accepts a valid start command", () => {
  const cmd = Command.parse({ action: "start", script: "app.py" });
  assert.equal(cmd.action, "start");
  assert.equal(cmd.script, "app.py");
});

test("Command.parse accepts a valid eval command", () => {
  const cmd = Command.parse({ action: "eval", expression: "x + 1" });
  assert.equal(cmd.action, "eval");
  assert.equal(cmd.expression, "x + 1");
});

test("Command.parse rejects an unknown action", () => {
  assert.throws(() => Command.parse({ action: "unknown" }));
});

test("Command.parse rejects start without script", () => {
  assert.throws(() => Command.parse({ action: "start" }));
});

test("Session starts in idle state", () => {
  const session = new Session();
  assert.equal(session.state, "idle");
});
