import type { Metadata } from "next";
import Link from "next/link";
import "./tokens.css";
import "./globals.css";

export const metadata: Metadata = {
  title: "Notchi",
  description: "A desktop pet that earns its own food while your coding agent works.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header className="top">
          <Link href="/" className="brand">
            Notchi
          </Link>
          <nav>
            <Link href="/pet">Get your pet</Link>
            <Link href="/brand">Fund a campaign</Link>
          </nav>
        </header>
        <main>{children}</main>
        <footer className="foot">Testnet build. Brains on 0G, humans verified by World.</footer>
      </body>
    </html>
  );
}
