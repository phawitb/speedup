import { createServer } from "node:http";

const port = Number(process.env.PORT || 8787);
const apiKey = process.env.GEMINI_API_KEY || process.env.OPENAI_API_KEY;
const provider = process.env.GEMINI_API_KEY ? "gemini" : "openai";
const model = process.env.GEMINI_MODEL || "gemini-flash-latest";
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

Use this fixed scoring rubric to decide the overallScore: Grammar 20%, Vocabulary 15%, Fluency 20%, Structure 15%,
Content/topic relevance 20%, Pronunciation 10%. Every value in categoryScores must still be a 0-100 score for that
category, not weighted points. Pronunciation is an estimate based only on supplied delivery metrics; explicitly avoid
claiming knowledge that the metrics do not support. Keep feedback concise. repeatedWords should include fillers or
conspicuously repeated content words, not normal function words.`;

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

function geminiSchema(value) {
  if (Array.isArray(value.type)) {
    const nonNull = value.type.find((item) => item !== "null") || "string";
    return { ...geminiSchema({ ...value, type: nonNull }), nullable: value.type.includes("null") };
  }
  const output = {};
  if (value.type) output.type = String(value.type).toUpperCase();
  if (value.properties) {
    output.properties = Object.fromEntries(
      Object.entries(value.properties).map(([key, property]) => [key, geminiSchema(property)]),
    );
  }
  if (value.items) output.items = geminiSchema(value.items);
  if (value.required) output.required = value.required;
  if (value.minimum != null) output.minimum = value.minimum;
  if (value.maximum != null) output.maximum = value.maximum;
  if (value.minItems != null) output.minItems = value.minItems;
  if (value.maxItems != null) output.maxItems = value.maxItems;
  return output;
}

function outputText(response) {
  return response?.candidates?.[0]?.content?.parts
    ?.map((part) => part.text || "")
    .join("")
    .trim() || null;
}

async function analyze(input) {
  if (!apiKey) throw Object.assign(new Error("GEMINI_API_KEY is not configured"), { status: 503 });
  const requestBody = {
      systemInstruction: {
        parts: [{ text: systemPrompt }],
      },
      contents: [
        {
          role: "user",
          parts: [{
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
      generationConfig: {
        temperature: 0.2,
        responseMimeType: "application/json",
        responseSchema: geminiSchema(schema),
      },
  };
  let request;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      request = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
        {
          method: "POST",
          signal: AbortSignal.timeout(75_000),
          headers: { "content-type": "application/json" },
          body: JSON.stringify(requestBody),
        },
      );
      if (request.status < 500 || attempt == 1) break;
    } catch {
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
    const message = response?.error?.message || `Gemini request failed (${request.status})`;
    throw Object.assign(new Error(message), { status: request.status >= 500 ? 502 : 400 });
  }
  const text = outputText(response);
  if (!text) throw Object.assign(new Error("Gemini returned no analysis"), { status: 502 });
  const result = JSON.parse(text);
  result.repeatedWords = Array.isArray(result.repeatedWords)
    ? Object.fromEntries(result.repeatedWords.map(({ word, count }) => [word, count]))
    : result.repeatedWords || {};
  return result;
}

export const server = createServer(async (req, res) => {
  if (req.method === "OPTIONS") return json(res, 204, {});
  if (req.method === "GET" && req.url === "/") {
    return json(res, 200, {
      service: "SpeakUp Analysis API",
      status: "ready",
      provider,
      model,
      apiKeyConfigured: Boolean(apiKey),
      endpoints: {
        health: "GET /health",
        analyze: "POST /analyze",
      },
    });
  }
  if (req.method === "GET" && req.url === "/health") {
    return json(res, 200, { ok: true, provider, model, apiKeyConfigured: Boolean(apiKey) });
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
