import type { Brief } from "./claims.js";

export const ACTIONS: string[];
export const MODEL_BY_MOOD: Record<string, string>;

/** Test seams: a different endpoint, key, fetch, timeout or token cap. */
export type ChatOptions = { base?: string; key?: string; fetch?: typeof fetch; timeoutMs?: number; maxTokens?: number };

export type ThinkResult = {
  action: string;
  say?: string;
  reason?: string;
  /** NEAR AI request id; null when no call was made */
  requestId: string | null;
  /** the completion id, set when a completion was served (and so billed) */
  completionId?: string | null;
  model?: string;
  usage?: unknown;
};
export function think(state: { event: string; mood: string; toolName?: string; notificationType?: string }, opts?: ChatOptions): Promise<ThinkResult>;

export type DiaryResult = { entry: string | null; reason?: string; requestId?: string | null; completionId?: string | null; model?: string };
export function diary(payload: Record<string, unknown>, opts?: ChatOptions): Promise<DiaryResult>;

export type Hook = { format: string; text: string; requestId: string | null };
export function suggestHooks(brief: Brief, opts?: ChatOptions): Promise<{ hooks: Hook[]; dropped: { format: string; text: string; reason: string }[]; requestId: string }>;
