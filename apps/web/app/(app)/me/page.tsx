import type { Metadata } from "next";
import Me from "./Me";
import { PRODUCT } from "@/lib/config";

// Server wrapper only so a shared /me?pet=... link previews with the pet's real recap card.
export function generateMetadata({ searchParams }: { searchParams: { pet?: string } }): Metadata {
  const pet = typeof searchParams.pet === "string" ? searchParams.pet.slice(0, 80) : "";
  if (!pet) return { title: `Your pet · ${PRODUCT}` };
  const image = `/me/card?pet=${encodeURIComponent(pet)}`;
  return {
    title: `${pet} · ${PRODUCT}`,
    description: "What this pet earned from sponsored hooks this week, read from the vault.",
    openGraph: { images: [image] },
    twitter: { card: "summary_large_image", images: [image] },
  };
}

export default function Page() {
  return <Me />;
}
