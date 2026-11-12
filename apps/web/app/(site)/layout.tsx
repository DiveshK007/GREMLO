import type { Metadata } from "next";
import { PRODUCT } from "@/lib/config";
import "./site.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_WEB_URL ?? "http://localhost:3000"),
  title: `${PRODUCT}: a pet for every agent`,
  description: "A desktop pet that lives in your notch, reacts to your coding agent, and earns its own food.",
};

// The 1.0 website has its own root layout: a dark desk with the notch at the top (docs/design/1.0/web).
export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,400..800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" />
      </head>
      <body>{children}</body>
    </html>
  );
}
