import type { Metadata } from "next";
import Me from "./Me";

// Server wrapper only so a shared /me?pet=... link previews with the pet's real recap card.
export function generateMetadata({ searchParams }: { searchParams: { pet?: string } }): Metadata {
  const pet = typeof searchParams.pet === "string" ? searchParams.pet.slice(0, 80) : "";
  if (!pet) return { title: "Your pet · Notchi" };
  const image = `/me/card?pet=${encodeURIComponent(pet)}`;
  return {
    title: `${pet} · Notchi`,
    description: "What this Notchi pet earned from sponsored hooks this week, read from the chain.",
    openGraph: { images: [image] },
    twitter: { card: "summary_large_image", images: [image] },
  };
}

export default function Page() {
  return <Me />;
}
