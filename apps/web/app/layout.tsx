import { PRODUCT } from "@/lib/config";
import type { Metadata } from "next";
import Link from "next/link";
import "./tokens.css";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_WEB_URL ?? "http://localhost:3000"), // absolute URLs for share cards
  title: PRODUCT,
  description: "A desktop pet that earns its own food while your coding agent works.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header className="top">
          <Link href="/" className="brand">
            {PRODUCT}
          </Link>
          <nav>
            <Link href="/pet">Get your pet</Link>
            <Link href="/me">Your pet</Link>
            <Link href="/brand">Fund a campaign</Link>
          </nav>
        </header>
        <main>{children}</main>
        <footer className="foot">Testnet build. Brains on NEAR AI Cloud (TEE inference), money on NEAR, humans verified by World.</footer>
      </body>
    </html>
  );
}
