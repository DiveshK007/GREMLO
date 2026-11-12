import Script from "next/script";
import { markup } from "./markup";

// The 1.0 website. The markup reads with no motion; site.js adds the physics pet, the pinned scenes and the
// sprites once GSAP, ScrollTrigger and Lenis (the design's exact versions) are in.
export default function Site() {
  return (
    <>
      <div id="site" dangerouslySetInnerHTML={{ __html: markup }} />
      <Script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js" strategy="afterInteractive" />
      <Script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/ScrollTrigger.min.js" strategy="afterInteractive" />
      <Script src="https://cdn.jsdelivr.net/npm/lenis@1.1.13/dist/lenis.min.js" strategy="afterInteractive" />
      <Script src="/site/site.js" strategy="afterInteractive" />
    </>
  );
}
