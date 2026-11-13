# Gremlo 1.0 · app pages: export for Claude Code

The eight app pages and the share image, redesigned on the home page's design. Desktop and phone, light and dark, every state.

| Path | What |
|---|---|
| `APP_PAGES_REDESIGN.md` | The spec: shared decisions, answers to the brief's open questions, bug fixes, copy changes, each page's states, API asks |
| `BUILD_BRIEF_app_pages.md` | Twelve build steps and the definition of done |
| `tokens.css` | 1.0 tokens with the real Light theme, `--accent-text`, and the radius decision. Replaces both old token files |
| `web/` | Clickable prototype. Serve the folder (`npx serve web`) and open `index.html`. **● STATE** (bottom right) walks every state; `?state=<id>&theme=light\|dark` deep-links one |
| `web/app.css`, `web/app.js` | Shared shell, components, theme switch, the bar notch, the canvas `Pet` renderer and plates |
| `screens/` | 205 screenshots: every state at desktop-dark and mobile-light, each page's first state also at desktop-light and mobile-dark, the share cards, and the phone menu |
| `og/card.tsx` | The `/me/card` route for next/og |
| `assets/stills/` | Pre-cut 384×416 stills per species (idle, celebrate, hold) for the share card |

The fonts come from Google Fonts in the prototype, and the sprites are the v6 sheets renamed for Gremlo (`gremlo.webp` is the bean). All data in the prototype is example data.
