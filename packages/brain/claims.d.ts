export type Brief = { product: string; audience: string; offer?: string; proof?: string; cta: string };
export const FORMATS: string[];
export const MIN_HOOK: number;
export const MAX_HOOK: number;
export const CLOSED: [string, RegExp][];
/** A reason the brief is refused, or null when it passes. */
export function checkBrief(brief: Brief): string | null;
/** A reason the hook is refused, or null when it passes. */
export function checkHook(text: string, brief: Brief): string | null;
