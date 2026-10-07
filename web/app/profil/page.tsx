import Link from "next/link";
import { loadDossier } from "@/lib/coach";
import { DEFAULT_PROFILE } from "@/lib/recordings";
import { detectLang, t } from "@/lib/i18n";

export const dynamic = "force-dynamic";

export default async function ProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ p?: string }>;
}) {
  const { p } = await searchParams;
  const profile = /^[a-z0-9-]{1,24}$/.test(p ?? "") ? p! : DEFAULT_PROFILE;
  const lang = await detectLang();
  const s = t(lang);

  const dossier = await loadDossier(profile);

  return (
    <>
      <Link href={`/?p=${profile}`} className="backlink">
        {s.allGames}
      </Link>
      <h2 className="page-title">{s.profileLink}</h2>

      {!dossier && <p className="empty">{s.profileEmpty}</p>}

      {dossier && (
        <>
          <p className="subtitle">{s.profileMeta(dossier.gamesAnalyzed)}</p>

          <div className="focus-card">
            <div className="focus-label">{s.nextFocus}</div>
            <div className="focus-text">{dossier.fokus}</div>
          </div>

          <h3 className="analysis-sub">{s.standort}</h3>
          <div className="prose">{dossier.standort}</div>

          <h3 className="analysis-sub">{s.plan}</h3>
          <div className="prose">{dossier.trainingsplan}</div>
        </>
      )}
    </>
  );
}
