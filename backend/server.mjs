import { createServer } from "node:http";

const port = Number(process.env.PORT || 8787);
const apiKey = process.env.OPENAI_API_KEY;
const model = process.env.OPENAI_MODEL || "gpt-5-mini";
const allowedOrigin = process.env.ALLOWED_ORIGIN || "*";

const schema = {
  type: "object",
  additionalProperties: false,
  required: [
    "overallScore",
    "categoryScores",
    "strengths",
    "improvements",
    "transcriptSentences",
    "revisedVersion",
    "revisedChanges",
    "repeatedWords",
  ],
  properties: {
    overallScore: { type: "integer", minimum: 0, maximum: 100 },
    categoryScores: {
      type: "object",
      additionalProperties: false,
      required: ["Fluency", "Content", "Structure", "Vocabulary", "Grammar", "Pronunciation"],
      properties: Object.fromEntries(
        ["Fluency", "Content", "Structure", "Vocabulary", "Grammar", "Pronunciation"].map(
          (name) => [name, { type: "integer", minimum: 0, maximum: 100 }],
        ),
      ),
    },
    strengths: { type: "array", minItems: 2, maxItems: 4, items: { type: "string" } },
    improvements: { type: "array", minItems: 2, maxItems: 4, items: { type: "string" } },
    transcriptSentences: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["original", "correction", "note", "startMs", "endMs"],
        properties: {
          original: { type: "string" },
          correction: { type: ["string", "null"] },
          note: { type: ["string", "null"] },
          startMs: { type: "integer", minimum: 0 },
          endMs: { type: "integer", minimum: 0 },
        },
      },
    },
    revisedVersion: { type: "string" },
    revisedChanges: { type: "array", minItems: 2, maxItems: 5, items: { type: "string" } },
    repeatedWords: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["word", "count"],
        properties: {
          word: { type: "string" },
          count: { type: "integer", minimum: 1 },
        },
      },
    },
  },
};

const systemPrompt = `You are SpeakUp, an English speaking coach. Analyze only the supplied transcript and metrics.
Return supportive, specific feedback in English. Preserve the learner's exact spoken words in original.
For each sentence, set correction and note to null when it is already natural. Correct only genuine grammar,
word-choice, or clarity problems. The revised version must preserve every central idea, add no facts, remain
close in length, remove fillers, improve transitions, and sound natural when spoken.

Use this fixed scoring rubric: Grammar 20%, Vocabulary 15%, Fluency 20%, Structure 15%, Content/topic relevance
20%, Pronunciation 10%. Pronunciation is an estimate based only on supplied delivery metrics; explicitly avoid
claiming knowledge that the metrics do not support. Keep feedback concise. repeatedWords should include fillers
or conspicuously repeated content words, not normal function words.`;

function json(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "access-control-allow-origin": allowedOrigin,
    "access-control-allow-headers": "content-type",
    "access-control-allow-methods": "GET,POST,OPTIONS",
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 256_000) throw Object.assign(new Error("Request is too large"), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw Object.assign(new Error("Invalid JSON"), { status: 400 });
  }
}

function validateInput(value) {
  if (!value || typeof value !== "object") return "A request body is required";
  if (typeof value.transcript !== "string" || value.transcript.trim().length < 2) return "Transcript is empty";
  if (value.transcript.length > 40_000) return "Transcript is too long";
  if (typeof value.topic !== "string" || !value.topic.trim()) return "Topic is required";
  return null;
}

function outputText(response) {
  for (const item of response.output || []) {
    for (const content of item.content || []) {
      if (content.type === "output_text" && content.text) return content.text;
    }
  }
  return null;
}

async function analyze(input) {
  if (!apiKey) throw Object.assign(new Error("OPENAI_API_KEY is not configured"), { status: 503 });
  const requestBody = {
      model,
      store: false,
      reasoning: { effort: "low" },
      input: [
        { role: "system", content: [{ type: "input_text", text: systemPrompt }] },
        {
          role: "user",
          content: [{
            type: "input_text",
            text: JSON.stringify({
              topic: input.topic,
              difficulty: input.difficulty || "random",
              durationSeconds: input.durationSeconds || 0,
              transcript: input.transcript.trim(),
              segments: Array.isArray(input.segments) ? input.segments : [],
              deliveryMetrics: input.deliveryMetrics || {},
            }),
          }],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "speakup_speech_analysis",
          strict: true,
          schema,
        },
      },
  };
  let request;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      request = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    signal: AbortSignal.timeout(75_000),
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(requestBody),
      });
      if (request.status < 500 || attempt == 1) break;
    } catch (error) {
      if (attempt == 1) {
        throw Object.assign(
          new Error("The AI service took too long. Please try again."),
          { status: 504 },
        );
      }
    }
  }
  const response = await request.json();
  if (!request.ok) {
    const message = response?.error?.message || `OpenAI request failed (${request.status})`;
    throw Object.assign(new Error(message), { status: request.status >= 500 ? 502 : 400 });
  }
  const text = outputText(response);
  if (!text) throw Object.assign(new Error("The model returned no analysis"), { status: 502 });
  const result = JSON.parse(text);
  result.repeatedWords = Object.fromEntries(result.repeatedWords.map(({ word, count }) => [word, count]));
  return result;
}

export const server = createServer(async (req, res) => {
  if (req.method === "OPTIONS") return json(res, 204, {});
  if (req.method === "GET" && req.url === "/") {
    return json(res, 200, {
      service: "SpeakUp Analysis API",
      status: "ready",
      model,
      apiKeyConfigured: Boolean(apiKey),
      endpoints: {
        health: "GET /health",
        analyze: "POST /analyze",
      },
    });
  }
  if (req.method === "GET" && req.url === "/health") {
    return json(res, 200, { ok: true, model, apiKeyConfigured: Boolean(apiKey) });
  }
  if (req.method !== "POST" || req.url !== "/analyze") return json(res, 404, { error: "Not found" });
  try {
    const body = await readJson(req);
    const error = validateInput(body);
    if (error) return json(res, 400, { error });
    return json(res, 200, await analyze(body));
  } catch (error) {
    console.error("analysis_failed", error?.message || error);
    return json(res, error.status || 500, { error: error.message || "Analysis failed" });
  }
});

if (process.env.NODE_ENV !== "test") {
  server.listen(port, "0.0.0.0", () => console.log(`SpeakUp backend listening on http://0.0.0.0:${port}`));
}
