/** A transaction that went through but whose result we couldn't use: the money moved, so say so. */
export class PaidError extends Error {
  constructor(public txHash: string, message: string) {
    super(message);
  }
}
