/** One pet-name rule everywhere (web /pet, server, Mac, the purse factory): 2-24 of a-z, 0-9 and dashes, not starting
 *  or ending with a dash, so the name is also a valid account. */
export const PET_NAME = /^[a-z0-9][a-z0-9-]{0,22}[a-z0-9]$/;
export const validPetName = (n: string) => PET_NAME.test(n);
/** What typing leaves in the field: lowercased, only allowed characters, at most 24. */
export const cleanPetName = (raw: string) => raw.toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 24);
/** Candidate free names after a clash: mochi-2, mochi-3, ... each still within 24 characters. */
export const nameCandidates = (base: string, from = 2, to = 19) =>
  Array.from({ length: to - from + 1 }, (_, i) => { const n = `-${from + i}`; return `${base.slice(0, 24 - n.length)}${n}`; });
