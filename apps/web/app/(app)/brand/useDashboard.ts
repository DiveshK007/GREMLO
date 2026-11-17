"use client";

import { useState } from "react";
import { arkivCampaign, campaignStats, settleImpressions, type ArkivView, type Settlement, type Stats } from "@/lib/api";
import { closeCampaign, readCampaign, topUpCampaign } from "@/lib/chain";
import { parseNear } from "@/lib/config";
import type { Lookup } from "./shared";

/** The campaign dashboard's state: look a campaign up, settle its views, top it up, close it. */
export function useDashboard({ account, busy: _busy, setBusy }: { account: string | null; busy: string; setBusy: (b: string) => void }) {
  const [lookupId, setLookupId] = useState("");
  const [lookup, setLookup] = useState<Lookup | null>(null);
  const [stats, setStats] = useState<Stats | null | undefined>(undefined);
  const [arkiv, setArkiv] = useState<ArkivView | null>(null);
  const [campaignError, setCampaignError] = useState("");
  const [refund, setRefund] = useState<{ txHash: string; amount: bigint } | null>(null);
  const [topUp, setTopUp] = useState("0.5");
  const [toppedUp, setToppedUp] = useState<{ txHash: string; amount: string } | null>(null);
  const [settlement, setSettlement] = useState<Settlement | null>(null);

  async function loadCampaign(id: string) {
    setCampaignError("");
    setRefund(null);
    setToppedUp(null);
    setSettlement(null);
    if (!/^\d+$/.test(id)) return setCampaignError("Enter a campaign ID number, like 2.");
    setBusy("lookup");
    try {
      const [l, s, a] = await Promise.all([readCampaign(BigInt(id)), campaignStats(id).catch(() => null), arkivCampaign(id).catch(() => null)]);
      setLookup(l);
      setStats(s);
      setArkiv(a);
      window.history.replaceState(null, "", `/brand?c=${id}`);
    } catch (e) {
      setLookup(null);
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function run(kind: string, f: () => Promise<void>) {
    setCampaignError("");
    setBusy(kind);
    try {
      await f();
    } catch (e) {
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }
  const onSettle = () =>
    run("settle", async () => {
      setSettlement(null);
      setSettlement(await settleImpressions(lookupId));
      setLookup(await readCampaign(BigInt(lookupId)));
    });
  const onClose = () =>
    run("close", async () => {
      if (!account) throw new Error("Connect the wallet that created this campaign first.");
      const res = await closeCampaign(account, BigInt(lookupId));
      setRefund({ txHash: res.txHash, amount: res.refund });
      setLookup(await readCampaign(BigInt(lookupId)));
    });
  const onTopUp = (e: React.FormEvent) => {
    e.preventDefault();
    setToppedUp(null);
    return run("topup", async () => {
      if (!account) throw new Error("Connect the wallet that created this campaign first.");
      let wei: bigint;
      try {
        wei = parseNear(topUp);
      } catch {
        throw new Error("Enter an amount in NEAR, like 0.5.");
      }
      if (wei <= 0n) throw new Error("Enter an amount in NEAR, like 0.5.");
      const txHash = await topUpCampaign(account, BigInt(lookupId), wei);
      setToppedUp({ txHash, amount: topUp });
      setLookup(await readCampaign(BigInt(lookupId)));
    });
  };

  return { lookupId, setLookupId, lookup, stats, arkiv, campaignError, refund, topUp, setTopUp, toppedUp, settlement, loadCampaign, onSettle, onClose, onTopUp };
}
export type Dashboard = ReturnType<typeof useDashboard>;
