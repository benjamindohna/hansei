import Link from "next/link";
import { notFound } from "next/navigation";
import { after } from "next/server";
import { loadAnalysis, runAnalysis } from "@/lib/coach";
import {
  loadGames,
  loadMeta,
  formatWeekday,
  formatShortDate,
  formatStats,
  formatRecTime,
  DEFAULT_PROFILE,
} from "@/lib/recordings";
import { detectLang, t } from "@/lib/i18n";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

export default async function GamePage({
  params,
  searchParams,
}: {
  params: Promise<{ session: string }>;
  searchParams: Promise<{ p?: string }>;
}) {
  const { session } = await params;
  const { p } = await searchParams;
  const profile = /^[a-z0-9-]{1,24}$/.test(p ?? "") ? p! : DEFAULT_PROFILE;
  const lang = await detectLang();
  const s = t(lang);

  const sessionEpoch = Number(session);
  if (!Number.isInteger(sessionEpoch)) notFound();

  const games = await loadGames(profile);
  const game = games.find((g) => g.sessionEpoch === sessionEpoch);
  if (!game) notFound();
  const stats = formatStats(await loadMeta(game));

  // Analyse laden; Selbstheilung: fehlt sie (oder kamen Notizen nach),
  // im Hintergrund neu anstoßen — sobald die Uploads 5 min zur Ruhe kamen.
  const analysis = await loadAnalysis(profile, sessionEpoch);
  const newestRec = Math.max(...game.recordings.map((r) => r.recEpoch));
  const settled = Date.now() / 1000 - newestRec > 300;
  if (
    settled &&
    (!analysis || analysis.analyzedRecCount < game.recordings.length)
  ) {
    after(async () => {
      await runAnalysis(profile, sessionEpoch).catch(() => {});
    });
  }

  const transcripts = await Promise.all(
    game.recordings.map(async (rec) => {
      if (!rec.transcriptUrl) return null;
      try {
        const res = await fetch(rec.transcriptUrl, { cache: "no-store" });
        return res.ok ? await res.text() : null;
      } catch {
        return null;
      }
    })
  );

  return (
    <>
      <Link href={`/?p=${profile}`} className="backlink">
        {s.allGames}
      </Link>
      <div className="game-head">
        <span className="game-day" style={{ fontSize: "1.3rem" }}>
          {formatWeekday(game.sessionEpoch, lang)}
        </span>
        <span className="game-date" style={{ fontSize: "1.1rem" }}>
          {formatShortDate(game.sessionEpoch, lang)}
        </span>
      </div>
      <p className="subtitle">
        {stats ? `${stats} · ` : ""}
        {game.recordings.length}{" "}
        {game.recordings.length === 1 ? s.note : s.notes}
      </p>

      {game.recordings.map((rec, i) => (
        <div key={rec.recEpoch} className="card">
          <div className="rec-head">
            <span className="rec-num">{i + 1}</span>
            <span className="card-meta">{formatRecTime(rec.recEpoch, lang)}</span>
          </div>
          {transcripts[i] ? (
            <p className="transcript">{transcripts[i]}</p>
          ) : (
            <p className="transcript missing">{s.noTranscript}</p>
          )}
          <audio controls preload="none" src={rec.audioUrl} />
        </div>
      ))}

      <h2 className="page-title section-title">{s.analysisTitle}</h2>
      {!analysis && <p className="analysis-pending">{s.analysisPending}</p>}
      {analysis && (
        <div className="analysis">
          <div className="prose">{analysis.spielanalyse}</div>

          {analysis.einordnung && (
            <>
              <h3 className="analysis-sub">{s.contextTitle}</h3>
              <div className="prose">{analysis.einordnung}</div>
            </>
          )}

          {analysis.fokusAuswertung && (
            <>
              <h3 className="analysis-sub">{s.focusReview}</h3>
              <div className="prose">{analysis.fokusAuswertung}</div>
            </>
          )}

          {analysis.fragen.length > 0 && (
            <>
              <h3 className="analysis-sub">{s.questions}</h3>
              {analysis.fragen.map((frage, i) => (
                <div key={i} className="question-card">
                  {frage}
                </div>
              ))}
            </>
          )}
        </div>
      )}
    </>
  );
}
