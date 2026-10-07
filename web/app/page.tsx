import Link from "next/link";
import {
  loadGames,
  loadMeta,
  loadProfiles,
  formatWeekday,
  formatShortDate,
  formatStats,
  DEFAULT_PROFILE,
} from "@/lib/recordings";
import { detectLang, t } from "@/lib/i18n";
import ProfileSwitcher from "./ProfileSwitcher";

export const dynamic = "force-dynamic";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ p?: string }>;
}) {
  const { p } = await searchParams;
  const profile = /^[a-z0-9-]{1,24}$/.test(p ?? "") ? p! : DEFAULT_PROFILE;
  const lang = await detectLang();
  const s = t(lang);

  const [profiles, games] = await Promise.all([
    loadProfiles(),
    loadGames(profile),
  ]);
  const metas = await Promise.all(games.map((g) => loadMeta(g)));

  return (
    <>
      <div className="title-row">
        <div>
          <h2 className="page-title">{s.games}</h2>
          <p className="subtitle" style={{ marginBottom: 0 }}>
            {s.subtitle}
          </p>
        </div>
        <div className="title-actions">
          <Link href={`/profil?p=${profile}`} className="profile-page-link">
            {s.profileLink}
          </Link>
          <ProfileSwitcher profiles={profiles} current={profile} />
        </div>
      </div>

      {games.length === 0 && <p className="empty">{s.empty}</p>}

      {games.map((game, i) => {
        const stats = formatStats(metas[i]);
        return (
          <Link
            key={game.sessionEpoch}
            href={`/spiel/${game.sessionEpoch}?p=${profile}`}
            className="card"
          >
            <div className="game-head">
              <span className="game-day">
                {formatWeekday(game.sessionEpoch, lang)}
              </span>
              <span className="game-date">
                {formatShortDate(game.sessionEpoch, lang)}
              </span>
            </div>
            {stats && <div className="card-meta">{stats}</div>}
          </Link>
        );
      })}
    </>
  );
}
