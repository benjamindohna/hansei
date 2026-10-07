import { put } from "@vercel/blob";
import { waitUntil } from "@vercel/functions";
import { runAnalysis } from "@/lib/coach";

export const maxDuration = 300;

// Gemini-Transkription mit Backoff-Retry: Bei vielen Uploads kurz nacheinander
// (Sync nach dem Spiel) schlägt sonst das Rate-Limit zu (HTTP 429).
async function transcribeWithRetry(audio: ArrayBuffer): Promise<Response> {
  const body = JSON.stringify({
    contents: [
      {
        parts: [
          {
            text: "Transcribe this voice note from a football player verbatim, in its original language (likely German, Spanish or English — do not translate). Return only the transcribed text, no quotes, no commentary.",
          },
          {
            inline_data: {
              mime_type: "audio/mp4",
              data: Buffer.from(audio).toString("base64"),
            },
          },
        ],
      },
    ],
  });
  let res: Response = new Response(null, { status: 500 });
  for (let attempt = 0; attempt < 3; attempt++) {
    res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${process.env.GEMINI_API_KEY}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body }
    );
    if (res.ok || (res.status < 500 && res.status !== 429)) return res;
    await new Promise((r) => setTimeout(r, 12_000 * (attempt + 1)));
  }
  return res;
}

// Nimmt eine Aufnahme von der iPhone-App entgegen, legt sie in Vercel Blob ab
// und transkribiert sie direkt per Whisper. Pfad-Konvention (deterministisch,
// damit Upload-Retries idempotent überschreiben statt Duplikate anzulegen):
//   recordings/<sessionEpoch>/<recEpoch>.m4a  +  gleicher Pfad .txt
export async function POST(req: Request) {
  const auth = req.headers.get("authorization");
  if (!process.env.UPLOAD_TOKEN || auth !== `Bearer ${process.env.UPLOAD_TOKEN}`) {
    return new Response("unauthorized", { status: 401 });
  }

  const { searchParams } = new URL(req.url);
  const session = searchParams.get("session") ?? "";
  if (!/^\d+$/.test(session)) {
    return new Response("bad params", { status: 400 });
  }
  // Profil-Segment; alte App-Versionen ohne Param landen beim Default-Profil.
  const profile = searchParams.get("profile") ?? "benni";
  if (!/^[a-z0-9-]{1,24}$/.test(profile)) {
    return new Response("bad profile", { status: 400 });
  }
  const dir = `recordings/${profile}/${session}`;

  // Session-Metadaten (Dauer, Distanz …) — kein Audio, keine Transkription.
  if (searchParams.get("kind") === "meta") {
    const body = await req.text();
    if (body.length > 10_000) return new Response("too large", { status: 400 });
    try {
      JSON.parse(body);
    } catch {
      return new Response("invalid json", { status: 400 });
    }
    await put(`${dir}/meta.json`, body, {
      access: "public",
      addRandomSuffix: false,
      allowOverwrite: true,
      contentType: "application/json",
    });
    // Die Meta-Datei kommt als Letztes durch die Sync-Pipeline — sie ist das
    // Signal "Session komplett": Coach-Analyse automatisch anstoßen.
    waitUntil(runAnalysis(profile, Number(session)).catch(() => {}));
    return Response.json({ ok: true });
  }

  const rec = searchParams.get("rec") ?? "";
  if (!/^\d+$/.test(rec)) {
    return new Response("bad params", { status: 400 });
  }

  const audio = await req.arrayBuffer();
  if (audio.byteLength < 1000) {
    return new Response("empty audio", { status: 400 });
  }

  const basePath = `${dir}/${rec}`;
  const blob = await put(`${basePath}.m4a`, audio, {
    access: "public",
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: "audio/mp4",
  });

  let transcript: string;
  try {
    const res = await transcribeWithRetry(audio);
    if (res.ok) {
      const json = await res.json();
      transcript =
        json.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ??
        "[Transkription leer]";
    } else {
      transcript = `[Transkription fehlgeschlagen: HTTP ${res.status}]`;
    }
  } catch {
    transcript = "[Transkription fehlgeschlagen]";
  }

  await put(`${basePath}.txt`, transcript, {
    access: "public",
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: "text/plain; charset=utf-8",
  });

  return Response.json({ ok: true, url: blob.url, transcript });
}
