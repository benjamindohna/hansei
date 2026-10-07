import { list } from "@vercel/blob";

export interface Recording {
  recEpoch: number;
  audioUrl: string;
  transcriptUrl?: string;
}

export interface GameMeta {
  duration?: number;
  distanceMeters?: number;
  calories?: number;
  avgHeartRate?: number;
}

export interface Game {
  sessionEpoch: number;
  recordings: Recording[];
  metaUrl?: string;
}

export const DEFAULT_PROFILE = "benni";

// Die Blob-Ablage ist die einzige Quelle der Wahrheit — keine Datenbank.
// Pfade: recordings/<profil>/<session>/<datei>; Altbestand ohne Profil-Segment
// zählt zum Default-Profil.
export async function loadProfiles(): Promise<string[]> {
  const { blobs } = await list({ prefix: "recordings/", limit: 1000 });
  const profiles = new Set<string>([DEFAULT_PROFILE]);
  for (const blob of blobs) {
    const match = blob.pathname.match(/^recordings\/([a-z0-9-]+)\/\d+\//);
    if (match) profiles.add(match[1]);
  }
  return [...profiles].sort();
}

export async function loadGames(profile: string): Promise<Game[]> {
  const prefix =
    profile === DEFAULT_PROFILE ? "recordings/" : `recordings/${profile}/`;
  const { blobs } = await list({ prefix, limit: 1000 });

  const games = new Map<number, Map<number, Recording>>();
  const metaUrls = new Map<number, string>();
  for (const blob of blobs) {
    // Für das Default-Profil zählen neue UND Legacy-Pfade.
    const rest =
      blob.pathname.match(
        new RegExp(`^recordings/${profile}/(\\d+)/(.+)$`)
      ) ??
      (profile === DEFAULT_PROFILE
        ? blob.pathname.match(/^recordings\/(\d+)\/(.+)$/)
        : null);
    if (!rest) continue;
    const sessionEpoch = Number(rest[1]);
    const file = rest[2];

    if (file === "meta.json") {
      metaUrls.set(sessionEpoch, blob.url);
      continue;
    }
    const fm = file.match(/^(\d+)\.(m4a|txt)$/);
    if (!fm) continue;
    const recEpoch = Number(fm[1]);
    const session = games.get(sessionEpoch) ?? new Map<number, Recording>();
    const rec = session.get(recEpoch) ?? { recEpoch, audioUrl: "" };
    if (fm[2] === "m4a") rec.audioUrl = blob.url;
    else rec.transcriptUrl = blob.url;
    session.set(recEpoch, rec);
    games.set(sessionEpoch, session);
  }

  return [...games.entries()]
    .map(([sessionEpoch, recs]) => ({
      sessionEpoch,
      recordings: [...recs.values()]
        .filter((r) => r.audioUrl)
        .sort((a, b) => a.recEpoch - b.recEpoch),
      metaUrl: metaUrls.get(sessionEpoch),
    }))
    .filter((g) => g.recordings.length > 0)
    .sort((a, b) => b.sessionEpoch - a.sessionEpoch);
}

export async function loadMeta(game: Game): Promise<GameMeta | null> {
  if (!game.metaUrl) return null;
  try {
    const res = await fetch(game.metaUrl, { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as GameMeta;
  } catch {
    return null;
  }
}

const TZ = "Europe/Berlin";
const DATE_LOCALES: Record<string, string> = {
  de: "de-DE",
  en: "en-GB",
  es: "es-ES",
};

export function formatWeekday(sessionEpoch: number, lang: string): string {
  return new Date(sessionEpoch * 1000).toLocaleDateString(
    DATE_LOCALES[lang] ?? "en-GB",
    { weekday: "long", timeZone: TZ }
  );
}

/** Tag + Monat; Jahr nur, wenn das Spiel vor dem laufenden Jahr liegt. */
export function formatShortDate(sessionEpoch: number, lang: string): string {
  const date = new Date(sessionEpoch * 1000);
  const withYear = date.getFullYear() < new Date().getFullYear();
  return date.toLocaleDateString(DATE_LOCALES[lang] ?? "en-GB", {
    day: "numeric",
    month: "long",
    ...(withYear ? { year: "numeric" } : {}),
    timeZone: TZ,
  });
}

export function formatStats(meta: GameMeta | null): string | null {
  if (!meta) return null;
  const parts: string[] = [];
  if (meta.duration && meta.duration > 0) {
    parts.push(`${Math.round(meta.duration / 60)} min`);
  }
  if (meta.distanceMeters && meta.distanceMeters > 0) {
    parts.push(
      `${(meta.distanceMeters / 1000).toFixed(1).replace(".", ",")} km`
    );
  }
  return parts.length ? parts.join(" · ") : null;
}

export function formatRecTime(recEpoch: number, lang: string): string {
  return new Date(recEpoch * 1000).toLocaleTimeString(
    DATE_LOCALES[lang] ?? "en-GB",
    { hour: "2-digit", minute: "2-digit", second: "2-digit", timeZone: TZ }
  );
}
