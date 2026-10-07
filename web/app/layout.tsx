import type { Metadata } from "next";
import Link from "next/link";
import { detectLang, t } from "@/lib/i18n";
import "./globals.css";

export const metadata: Metadata = {
  title: "Hansei",
  description: "Reflexion im Spiel — Sprachnotizen, transkribiert",
};

function EnsoMark({ size = 40 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" aria-hidden="true">
      <circle
        cx="24"
        cy="24"
        r="17"
        fill="none"
        stroke="currentColor"
        strokeWidth="4.5"
        strokeLinecap="round"
        strokeDasharray="94 13"
        transform="rotate(-56 24 24)"
      />
      <circle cx="37.5" cy="12.5" r="3.4" fill="#c7452d" />
    </svg>
  );
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const lang = await detectLang();
  return (
    <html lang={lang}>
      <body>
        <main>
          <Link href="/" className="brand">
            <EnsoMark />
            <span>
              <span className="brand-name">Hansei</span>
              <span className="brand-claim" style={{ display: "block" }}>
                {t(lang).claim}
              </span>
            </span>
          </Link>
          {children}
        </main>
      </body>
    </html>
  );
}
