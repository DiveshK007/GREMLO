import { HttpError } from "./register.ts";

// Viewability standard (README): a paid view is the sign on screen for at least 5 s, on an unlocked screen,
// not covered (the sign's window reports itself visible), with user input in the last 5 minutes.
// The Mac measures these and they're inside the device-signed body, so a script can't fake them without the key.
export const MIN_SHOWN_MS = 5_000;
export const MAX_IDLE_S = 300;

/** Throws 400 with the first rule a view breaks; returns nothing when it counts. */
export function checkViewable(v: any) {
  const shownMs = Number(v?.shownMs), idleS = Number(v?.idleS);
  if (!Number.isFinite(shownMs) || shownMs < MIN_SHOWN_MS) throw new HttpError(400, "view not counted: the sign was on screen under 5 seconds");
  if (v?.unlocked !== true) throw new HttpError(400, "view not counted: the screen was locked");
  if (v?.visible !== true) throw new HttpError(400, "view not counted: the sign was covered");
  if (!Number.isFinite(idleS) || idleS < 0 || idleS > MAX_IDLE_S) throw new HttpError(400, "view not counted: nobody was at the Mac");
}
