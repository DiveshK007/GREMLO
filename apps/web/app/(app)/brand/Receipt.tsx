"use client";

import { formatNear, formatWhen } from "@/lib/config";
import { toast } from "@/components/Shell";
import { ReceiptStage, Tx, type Funded } from "./shared";

/** What the brand sees after paying: the receipt, or "paid, hooks not saved yet" with Retry. */
export function Receipt({
  funded,
  retrying,
  retryError,
  retrySave,
  share,
  copied,
  onView,
  onAnother,
}: {
  funded: Funded;
  retrying: boolean;
  retryError: string;
  retrySave: () => void;
  share: (id: string) => void;
  copied: boolean;
  onView: (id: string) => void;
  onAnother: () => void;
}) {
  const unsaved = !!funded.recordWarning;
  return (
    <>
      <div className="wrap narrow" style={{ maxWidth: 1040 }}>
        <div className="end" style={{ paddingBottom: 20 }}>
          {unsaved && (
            <div className="bad" role="alert" style={{ maxWidth: "62ch", textAlign: "left", padding: "14px 16px", borderRadius: "var(--r-field)", background: "var(--surface)" }}>
              {funded.recordWarning}
              {retryError && <> Retry failed: {retryError}</>}
            </div>
          )}
          <span className="pill live">
            <i />
            Campaign #{funded.campaignId.toString()} · {unsaved ? "paid, not saved" : "live"}
          </span>
          <h1 className="dsp">{unsaved ? "Paid. Hooks not saved yet." : "Your campaign is live."}</h1>
          <p>
            {unsaved
              ? "Nothing shows to developers until the hooks are saved. Keep the receipt below; it proves the payment."
              : "Developers will see your hooks the next time their coding agent starts working. You pay only for real, verified views."}
          </p>
          {!unsaved && <ReceiptStage lines={funded.hooks} />}
        </div>
        <div className="flow c3">
          <div>
            <i>Budget</i>
            <span className="v">{formatNear(funded.budgetWei)}</span>
            <p>NEAR</p>
          </div>
          <div>
            <i>Price per view</i>
            <span className="v">{formatNear(funded.rateWei)}</span>
            <p>NEAR</p>
          </div>
          <div>
            <i>Estimated views</i>
            <span className="v">{(funded.budgetWei / funded.rateWei).toString()}</span>
            <p>an estimate, not a promise</p>
          </div>
          <div style={{ gridColumn: "span 2" }}>
            <i>Ends</i>
            <b>{formatWhen(Number(funded.endTime) * 1000)}</b>
            <p>Views are paid until 1 hour later, then the rest is refunded.</p>
          </div>
          <div>
            <i>Receipt</i>
            <Tx hash={funded.txHash} />
          </div>
        </div>
        <div className="actions" style={{ justifyContent: "center", marginTop: 30 }}>
          {unsaved ? (
            <>
              <button type="button" className="btn solid" onClick={retrySave} disabled={retrying} aria-busy={retrying}>
                {retrying ? "Saving…" : "Retry saving"}
              </button>
              <button
                type="button"
                className="btn ghost"
                onClick={() => {
                  void navigator.clipboard?.writeText(`Campaign #${funded.campaignId} · tx ${funded.txHash}`);
                  toast("Receipt copied");
                }}
              >
                Copy receipt
              </button>
              <a className="btn ghost" href={`mailto:help@gremlo.dev?subject=${encodeURIComponent(`Campaign #${funded.campaignId} hooks not saved`)}&body=${encodeURIComponent(`Receipt: ${funded.txHash}`)}`}>
                Contact us
              </a>
            </>
          ) : (
            <>
              <button type="button" className="btn solid" onClick={() => onView(funded.campaignId.toString())}>
                View dashboard
              </button>
              <button type="button" className="btn ghost" onClick={() => share(funded.campaignId.toString())}>
                {copied ? "Link copied" : "Copy share link"}
              </button>
              <button type="button" className="btn" onClick={onAnother}>
                Start another
              </button>
            </>
          )}
        </div>
      </div>
    </>
  );
}
