/** An inbound request body: an object whose values are unknown until a handler checks them. */
export type Body = Record<string, unknown>;

/**
 * JSON from a third party (NEAR RPC outcomes, the World portal's reply, a proof, a pet pack's pet.json) that code
 * walks with optional chaining and checks at the point it matters. Typing every shape here would mean copying other
 * services' schemas, which change without notice; this is the one place `any` stays, on purpose.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Loose = any;

/** A caught value that may carry the extra fields our own throw sites attach. */
export type Coded = Error & { code?: string; requestId?: string; unconfirmedTx?: string; txHash?: string };
export const coded = (e: unknown) => e as Coded;
