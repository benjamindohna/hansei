"use client";

import { useRouter } from "next/navigation";

export default function ProfileSwitcher({
  profiles,
  current,
}: {
  profiles: string[];
  current: string;
}) {
  const router = useRouter();
  return (
    <select
      className="profile-switch"
      value={current}
      onChange={(e) => router.push(`/?p=${e.target.value}`)}
      aria-label="Profil"
    >
      {profiles.map((p) => (
        <option key={p} value={p}>
          {p.charAt(0).toUpperCase() + p.slice(1)}
        </option>
      ))}
    </select>
  );
}
