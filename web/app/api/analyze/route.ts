import { runAnalysis } from "@/lib/coach";

export const maxDuration = 300;

// Interner Endpoint: führt die Coach-Analyse für eine Session aus.
// Wird von der Upload-Route (nach Meta-Eingang) und der Selbstheilung
// auf der Spielseite aufgerufen — nie vom User direkt.
export async function POST(req: Request) {
  const auth = req.headers.get("authorization");
  if (!process.env.UPLOAD_TOKEN || auth !== `Bearer ${process.env.UPLOAD_TOKEN}`) {
    return new Response("unauthorized", { status: 401 });
  }
  const { searchParams } = new URL(req.url);
  const profile = searchParams.get("profile") ?? "";
  const session = searchParams.get("session") ?? "";
  if (!/^[a-z0-9-]{1,24}$/.test(profile) || !/^\d+$/.test(session)) {
    return new Response("bad params", { status: 400 });
  }

  const analysis = await runAnalysis(profile, Number(session));
  return Response.json({ ok: analysis !== null });
}
