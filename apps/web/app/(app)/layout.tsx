import { PRODUCT } from "@/lib/config";
import type { Metadata } from "next";
import { Shell } from "@/components/Shell";
import "../tokens.css";
import "./app.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_WEB_URL ?? "http://localhost:3000"), // absolute URLs for share cards
  title: PRODUCT,
  description: "A desktop pet that earns its own food while your coding agent works.",
};

// Sets an explicit Light or Dark before first paint; no attribute means follow the system (tokens.css).
const THEME = `(function(){try{var t=localStorage.getItem('gremlo.theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}})()`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME }} />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,400..800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" />
      </head>
      <body data-pet="gremlo">
        <Shell>{children}</Shell>
      </body>
    </html>
  );
}
