import { headers } from "next/headers";

export type Lang = "de" | "en" | "es";

const STRINGS = {
  de: {
    claim: "Reflexion im Spiel",
    games: "Spiele",
    subtitle: "Jede Session, jede Notiz — automatisch transkribiert",
    empty:
      "Noch keine Aufnahmen. Starte eine Session auf der Watch — nach dem Sync aufs iPhone landen die Notizen automatisch hier.",
    note: "Notiz",
    notes: "Notizen",
    allGames: "← Alle Spiele",
    noTranscript: "Noch kein Transkript",
    analysisTitle: "Analyse des Coaches",
    analysisPending:
      "Der Coach analysiert dieses Spiel — die Analyse erscheint hier automatisch in wenigen Minuten.",
    contextTitle: "Einordnung ins Gesamtbild",
    focusReview: "Auswertung deines Fokus",
    nextFocus: "Dein Fokus fürs nächste Spiel",
    questions: "Fragen des Coaches",
    profileLink: "Dein Bild",
    profileEmpty:
      "Noch kein Bild vorhanden — nach deinem ersten analysierten Spiel entsteht es hier automatisch.",
    standort: "Standortbestimmung",
    plan: "Trainingsplan",
    profileMeta: (n: number) =>
      `Basierend auf ${n} ${n === 1 ? "analysierten Spiel" : "analysierten Spielen"}`,
  },
  en: {
    claim: "Reflection in the game",
    games: "Matches",
    subtitle: "Every session, every note — transcribed automatically",
    empty:
      "No recordings yet. Start a session on the watch — once it syncs to the iPhone, your notes show up here automatically.",
    note: "note",
    notes: "notes",
    allGames: "← All matches",
    noTranscript: "No transcript yet",
    analysisTitle: "Coach's analysis",
    analysisPending:
      "The coach is analyzing this match — the analysis will appear here automatically in a few minutes.",
    contextTitle: "The bigger picture",
    focusReview: "Review of your focus",
    nextFocus: "Your focus for the next match",
    questions: "Questions from the coach",
    profileLink: "Your picture",
    profileEmpty:
      "No picture yet — it will build automatically after your first analyzed match.",
    standort: "Where you stand",
    plan: "Training plan",
    profileMeta: (n: number) =>
      `Based on ${n} analyzed ${n === 1 ? "match" : "matches"}`,
  },
  es: {
    claim: "Reflexión en el juego",
    games: "Partidos",
    subtitle: "Cada sesión, cada nota — transcrita automáticamente",
    empty:
      "Aún no hay grabaciones. Inicia una sesión en el reloj — al sincronizarse con el iPhone, tus notas aparecen aquí automáticamente.",
    note: "nota",
    notes: "notas",
    allGames: "← Todos los partidos",
    noTranscript: "Aún sin transcripción",
    analysisTitle: "Análisis del entrenador",
    analysisPending:
      "El entrenador está analizando este partido — el análisis aparecerá aquí automáticamente en unos minutos.",
    contextTitle: "La imagen completa",
    focusReview: "Evaluación de tu enfoque",
    nextFocus: "Tu enfoque para el próximo partido",
    questions: "Preguntas del entrenador",
    profileLink: "Tu perfil",
    profileEmpty:
      "Aún no hay perfil — se creará automáticamente tras tu primer partido analizado.",
    standort: "Dónde estás",
    plan: "Plan de entrenamiento",
    profileMeta: (n: number) =>
      `Basado en ${n} ${n === 1 ? "partido analizado" : "partidos analizados"}`,
  },
} as const;

export async function detectLang(): Promise<Lang> {
  const accept = (await headers()).get("accept-language") ?? "";
  const primary = accept.split(",")[0]?.trim().toLowerCase() ?? "";
  if (primary.startsWith("de")) return "de";
  if (primary.startsWith("es")) return "es";
  return "en";
}

export function t(lang: Lang) {
  return STRINGS[lang];
}
