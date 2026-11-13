import type { Metadata } from "next";
import { PRODUCT } from "@/lib/config";
import "./site.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_WEB_URL ?? "http://localhost:3000"),
  title: `${PRODUCT}: a pet for every agent`,
  description: "A desktop pet that lives in your notch, reacts to your coding agent, and earns its own food.",
};

// The home page's styles need a resolved theme, so System is resolved here before first paint (key gremlo.theme,
// shared with the app pages); site.js keeps it in step after that.
const THEME = `(function(){var t;try{t=localStorage.getItem('gremlo.theme')}catch(e){}if(t!=='light'&&t!=='dark')t=matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t})()`;

// The 1.0 website has its own root layout: a dark desk with the notch at the top (docs/design/1.0/web).
export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME }} />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,400..800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" />
      </head>
      <body>{children}</body>
    </html>
  );
}
