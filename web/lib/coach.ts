import Anthropic from "@anthropic-ai/sdk";
import { list, put } from "@vercel/blob";

// Der Experte: liest alle Notizen eines Spiels + das Dossier (sein Gedächtnis),
// schreibt Spielanalyse + fortgeschriebenes Dossier zurück in den Blob.
// Läuft vollautomatisch — getriggert vom Upload der Session-Meta-Datei,
// mit Selbstheilung beim Seitenaufruf.

export interface GameAnalysis {
  spielanalyse: string;
  einordnung: string | null;
  fokusAuswertung: string | null;
  fragen: string[];
  analyzedRecCount: number;
  createdAt: string;
}

export interface Dossier {
  standort: string;
  trainingsplan: string;
  fokus: string;
  intern: string;
  lastSessionEpoch: number;
  gamesAnalyzed: number;
  updatedAt: string;
}

const OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    spielanalyse: {
      type: "string",
      description:
        "Isolierte Analyse dieses Spiels auf Basis der Notizen. Fließtext-Absätze, keine Markdown-Syntax.",
    },
    einordnung: {
      type: ["string", "null"],
      description:
        "Einordnung ins Gesamtbild über mehrere Spiele (null beim ersten Spiel). Fließtext.",
    },
    fokus_auswertung: {
      type: ["string", "null"],
      description:
        "Auswertung des Fokus, den der Spieler fürs Spiel mitbekommen hatte (null, wenn es keinen gab). Fließtext.",
    },
    naechster_fokus: {
      type: "string",
      description:
        "EIN konkreter Fokus für das nächste Spiel, 1-2 Sätze, direkt ansprechend formuliert.",
    },
    fragen: {
      type: "array",
      items: { type: "string" },
      description:
        "0-2 gezielte Rückfragen, die ein Profi jetzt stellen würde (der Spieler ist nicht mehr im Spiel, Fragen müssen allgemein beantwortbar sein).",
    },
    dossier_standort: {
      type: "string",
      description:
        "Standortbestimmung: die 2-3 wichtigsten Problemfelder als Fließtext mit Ursachenketten und wörtlichen Zitaten aus den Notizen.",
    },
    dossier_trainingsplan: {
      type: "string",
      description:
        "Trainingsplan: 2-3 Übungen mit Begründungskette (liegt an → trainiert durch → so genau → woran du Fortschritt merkst). Fließtext mit Absätzen.",
    },
    dossier_intern: {
      type: "string",
      description:
        "Interne Notizen des Experten an sein zukünftiges Ich: Hypothesen, offene Fragen, was er beim nächsten Spiel prüfen will. Wird dem Spieler nicht gezeigt.",
    },
  },
  required: [
    "spielanalyse",
    "einordnung",
    "fokus_auswertung",
    "naechster_fokus",
    "fragen",
    "dossier_standort",
    "dossier_trainingsplan",
    "dossier_intern",
  ],
  additionalProperties: false,
} as const;

const SYSTEM_PROMPT = `Du bist ein erfahrener Fußballtrainer und Experte für individuelle Spielerentwicklung. Ein Amateurspieler nimmt mitten im Spiel kurze Sprachnotizen über seine eigenen Fehler auf. Du bekommst die Transkripte aller Notizen eines Spiels und dein Dossier über den Spieler (dein Gedächtnis aus früheren Spielen).

Deine Aufgabe: Lies zwischen den Zeilen wie ein Profi, der den Spieler wirklich verstehen will. Erkenne Muster und Ursachen hinter den Fehlern — nicht nur die Symptome.

Eiserne Regeln:
1. EVIDENZPFLICHT: Jede Diagnose zitiert die eigenen Worte des Spielers (in Anführungszeichen). Keine Behauptung ohne Beleg aus den Notizen.
2. KAUSALKETTEN: Nicht "du hast Probleme im Passspiel", sondern: woran es konkret liegt (a, b, c mit Evidenz) → was das trainiert → wie genau (Übung mit Aufbau und Dosierung) → woran der Spieler Fortschritt erkennt. Keine generischen Tipps wie "mehr Rondos".
3. RADIKALE VERKNAPPUNG: Maximal 2-3 Problemfelder, genau EIN Spielfokus, 2-3 Übungen. Ein Coach, der elf Baustellen nennt, ist ein Generator, kein Experte.
4. EHRLICHKEIT: Nach einem Spiel kennst du den Spieler kaum — sag das. Formuliere Hypothesen als Hypothesen ("dafür habe ich noch zu wenig Daten"). Vertrauen entsteht durch Nachhalten, nicht durch vorgetäuschte Gewissheit.
5. KONTINUITÄT: Beziehe dich explizit auf dein Dossier. Wenn ein bekanntes Problem wieder auftaucht oder verschwindet, benenne das. Werte den mitgegebenen Fokus ehrlich aus.
6. TRANSKRIPT-REALISMUS: Die Transkripte entstehen bei Lärm und Atemlosigkeit — einzelne Wörter können falsch sein. Deute robust, markiere Unsicheres.
7. RESSOURCEN: Übungen müssen allein, mit 1-2 Freunden oder mit einfachem Equipment machbar sein. Erwähne bei jeder Übung, was sie braucht.

Sprache: Antworte in der Sprache der Notizen (deutsch → deutsch, spanisch → spanisch, englisch → englisch). Sprich den Spieler direkt mit "du" an. Schreibe Fließtext-Absätze ohne Markdown-Überschriften, ohne Aufzählungszeichen-Syntax, ohne Fettdruck-Sternchen.`;

async function fetchText(url: string): Promise<string | null> {
  try {
    const res = await fetch(url, { cache: "no-store" });
    return res.ok ? await res.text() : null;
  } catch {
    return null;
  }
}

export async function loadDossier(profile: string): Promise<Dossier | null> {
  const { blobs } = await list({
    prefix: `recordings/${profile}/dossier.json`,
    limit: 1,
  });
  if (!blobs.length) return null;
  const text = await fetchText(blobs[0].url);
  if (!text) return null;
  try {
    return JSON.parse(text) as Dossier;
  } catch {
    return null;
  }
}

export async function loadAnalysis(
  profile: string,
  sessionEpoch: number
): Promise<GameAnalysis | null> {
  const { blobs } = await list({
    prefix: `recordings/${profile}/${sessionEpoch}/analysis.json`,
    limit: 1,
  });
  if (!blobs.length) return null;
  const text = await fetchText(blobs[0].url);
  if (!text) return null;
  try {
    return JSON.parse(text) as GameAnalysis;
  } catch {
    return null;
  }
}

/** Sammelt Transkripte + Meta einer Session aus dem Blob. */
async function loadSessionInput(profile: string, sessionEpoch: number) {
  const { blobs } = await list({
    prefix: `recordings/${profile}/${sessionEpoch}/`,
    limit: 200,
  });
  const transcripts: { recEpoch: number; text: string }[] = [];
  let meta: Record<string, number> | null = null;

  for (const blob of blobs) {
    const file = blob.pathname.split("/").pop() ?? "";
    if (file === "meta.json") {
      const text = await fetchText(blob.url);
      if (text) {
        try {
          meta = JSON.parse(text);
        } catch {}
      }
    } else if (file.endsWith(".txt")) {
      const recEpoch = Number(file.replace(".txt", ""));
      const text = await fetchText(blob.url);
      if (text && Number.isInteger(recEpoch)) {
        transcripts.push({ recEpoch, text: text.trim() });
      }
    }
  }
  transcripts.sort((a, b) => a.recEpoch - b.recEpoch);
  return { transcripts, meta };
}

function buildUserPrompt(
  sessionEpoch: number,
  transcripts: { recEpoch: number; text: string }[],
  meta: Record<string, number> | null,
  dossier: Dossier | null
): string {
  const date = new Date(sessionEpoch * 1000).toLocaleDateString("de-DE", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "Europe/Berlin",
  });

  const notes = transcripts
    .map((t, i) => {
      const minute = Math.max(
        0,
        Math.round((t.recEpoch - sessionEpoch) / 60)
      );
      return `Notiz ${i + 1} (Spielminute ~${minute}): "${t.text}"`;
    })
    .join("\n");

  const metaLine = meta
    ? `Spieldauer: ${Math.round((meta.duration ?? 0) / 60)} min, Laufdistanz: ${((meta.distanceMeters ?? 0) / 1000).toFixed(1)} km, Ø-Puls: ${Math.round(meta.avgHeartRate ?? 0)} bpm`
    : "Keine Workout-Daten vorhanden.";

  const dossierBlock = dossier
    ? `DEIN DOSSIER ÜBER DEN SPIELER (Stand: nach ${dossier.gamesAnalyzed} ${dossier.gamesAnalyzed === 1 ? "Spiel" : "Spielen"}):
Standortbestimmung: ${dossier.standort}
Aktueller Trainingsplan: ${dossier.trainingsplan}
Fokus, den du dem Spieler für DIESES Spiel mitgegeben hattest: ${dossier.fokus}
Deine internen Notizen: ${dossier.intern}`
    : `Dies ist das ERSTE Spiel, das du von diesem Spieler analysierst. Du hast noch kein Dossier — sei entsprechend vorsichtig mit Urteilen und formuliere Hypothesen. "einordnung" und "fokus_auswertung" sind daher null.`;

  return `${dossierBlock}

NEUES SPIEL vom ${date}:
${metaLine}

Die ${transcripts.length} Sprachnotizen des Spielers aus dem Spiel:
${notes}

Analysiere das Spiel und schreibe dein Dossier fort.`;
}

/**
 * Führt die komplette Analyse durch und persistiert analysis.json + dossier.json.
 * Idempotent: erneuter Lauf überschreibt.
 */
export async function runAnalysis(
  profile: string,
  sessionEpoch: number
): Promise<GameAnalysis | null> {
  const { transcripts, meta } = await loadSessionInput(profile, sessionEpoch);
  if (transcripts.length === 0) return null;

  const dossier = await loadDossier(profile);

  const client = new Anthropic();
  const stream = client.messages.stream({
    model: "claude-opus-5",
    max_tokens: 16000,
    system: SYSTEM_PROMPT,
    output_config: {
      format: {
        type: "json_schema",
        schema: OUTPUT_SCHEMA as unknown as Record<string, unknown>,
      },
    },
    messages: [
      {
        role: "user",
        content: buildUserPrompt(sessionEpoch, transcripts, meta, dossier),
      },
    ],
  });
  const message = await stream.finalMessage();

  if (message.stop_reason === "refusal") return null;
  const textBlock = message.content.find((b) => b.type === "text");
  if (!textBlock || textBlock.type !== "text") return null;

  const out = JSON.parse(textBlock.text) as {
    spielanalyse: string;
    einordnung: string | null;
    fokus_auswertung: string | null;
    naechster_fokus: string;
    fragen: string[];
    dossier_standort: string;
    dossier_trainingsplan: string;
    dossier_intern: string;
  };

  const analysis: GameAnalysis = {
    spielanalyse: out.spielanalyse,
    einordnung: out.einordnung,
    fokusAuswertung: out.fokus_auswertung,
    fragen: out.fragen ?? [],
    analyzedRecCount: transcripts.length,
    createdAt: new Date().toISOString(),
  };

  const newDossier: Dossier = {
    standort: out.dossier_standort,
    trainingsplan: out.dossier_trainingsplan,
    fokus: out.naechster_fokus,
    intern: out.dossier_intern,
    lastSessionEpoch: sessionEpoch,
    gamesAnalyzed: (dossier?.gamesAnalyzed ?? 0) + (dossier?.lastSessionEpoch === sessionEpoch ? 0 : 1),
    updatedAt: new Date().toISOString(),
  };

  const blobOpts = {
    access: "public" as const,
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: "application/json",
  };
  await put(
    `recordings/${profile}/${sessionEpoch}/analysis.json`,
    JSON.stringify(analysis),
    blobOpts
  );
  await put(
    `recordings/${profile}/dossier.json`,
    JSON.stringify(newDossier),
    blobOpts
  );

  return analysis;
}
