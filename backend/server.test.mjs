import assert from "node:assert/strict";
import { after, before, test } from "node:test";

process.env.NODE_ENV = "test";
const { server } = await import("./server.mjs");
let baseUrl;

before(async () => {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => new Promise((resolve) => server.close(resolve)));

test("health reports configuration without exposing the key", async () => {
  const response = await fetch(`${baseUrl}/health`);
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(typeof body.apiKeyConfigured, "boolean");
  assert.equal(JSON.stringify(body).includes("sk-"), false);
});

test("root describes the available API endpoints", async () => {
  const response = await fetch(`${baseUrl}/`);
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.status, "ready");
  assert.equal(body.endpoints.analyze, "POST /analyze");
});

test("analysis rejects an empty transcript before calling OpenAI", async () => {
  const response = await fetch(`${baseUrl}/analyze`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ topic: "A favorite place", transcript: "" }),
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "Transcript is empty");
});
