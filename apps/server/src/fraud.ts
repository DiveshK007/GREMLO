// Holdback and fraud rules for views. Views wait HOLDBACK_HOURS before they can be paid; then fixed rules decide.
// Flagged views are voided with a reason the brand can see. No model is involved and nothing is guessed.

export type Held = { pet: string; hour: number; ip: string; n: number }; // hour = unix hours; ip = short hash, never raw
export const MAX_PETS_PER_IP_HOUR = 3; // one household or office, not a farm
export const MAX_ACTIVE_HOURS_PER_DAY = 20; // a human sleeps; a script doesn't

/** Splits matured entries (older than `holdHours`) into paid and voided; younger ones keep waiting. */
export function review(held: Held[], nowHour: number, holdHours: number) {
  const due = held.filter((h) => nowHour - h.hour >= holdHours);
  const waiting = held.filter((h) => nowHour - h.hour < holdHours);
  const petsPerIpHour = new Map<string, Set<string>>();
  const hoursPerPetDay = new Map<string, Set<number>>();
  // rules look at everything we still hold, so a farm can't hide by spreading across the boundary
  for (const h of held) {
    (petsPerIpHour.get(`${h.ip}:${h.hour}`) ?? petsPerIpHour.set(`${h.ip}:${h.hour}`, new Set()).get(`${h.ip}:${h.hour}`)!).add(h.pet);
    const day = `${h.pet}:${Math.floor(h.hour / 24)}`;
    (hoursPerPetDay.get(day) ?? hoursPerPetDay.set(day, new Set()).get(day)!).add(h.hour);
  }
  const ok: Held[] = [], voided: (Held & { reason: string })[] = [];
  for (const h of due) {
    if (petsPerIpHour.get(`${h.ip}:${h.hour}`)!.size > MAX_PETS_PER_IP_HOUR) voided.push({ ...h, reason: "too many pets from one network in an hour" });
    else if (hoursPerPetDay.get(`${h.pet}:${Math.floor(h.hour / 24)}`)!.size > MAX_ACTIVE_HOURS_PER_DAY) voided.push({ ...h, reason: "views around the clock" });
    else ok.push(h);
  }
  return { ok, voided, waiting };
}

/** Adds one view to the held list, merging into the pet's bucket for that hour and network. */
export function hold(held: Held[], pet: string, hour: number, ip: string) {
  const b = held.find((h) => h.pet === pet && h.hour === hour && h.ip === ip);
  if (b) b.n++;
  else held.push({ pet, hour, ip, n: 1 });
  return held;
}
