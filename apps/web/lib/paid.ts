/** The wallet gave back no transaction hash, so we can't say whether anything was sent. Never claim a payment then. */
export class UnsureError extends Error {
  constructor() {
    super("Check your wallet. We can't tell if this was sent.");
  }
}

/** A transaction that went through but whose result we couldn't use: the money moved, so say so. */
export class PaidError extends Error {
  constructor(
    public txHash: string,
    message: string,
  ) {
    super(message);
  }
}
