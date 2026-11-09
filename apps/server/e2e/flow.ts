// End-to-end on a local Anvil chain: register (World stubbed at its HTTP boundary) -> fund onchain -> views -> settle,
// then check the payout landed onchain. Denied paths too. CI only: it expects Anvil on :8545 and `forge build` done.
// No 0G call is made; nothing here runs against a real network.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import { createPublicClient, createWalletClient, defineChain, http, keccak256, parseAbi, parseEther, toBytes } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { signalHash } from "../src/register.ts";

const RPC = "http://127.0.0.1:8545", API = "http://127.0.0.1:8799", WORLD_PORT = 8798;
const KEYS = [ // Anvil's public test accounts
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
] as const;
const chain = defineChain({ id: 31337, name: "anvil", nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [RPC] } } });
const pub = createPublicClient({ chain, transport: http() });
const wallet = (k: `0x${string}`) => createWalletClient({ chain, transport: http(), account: privateKeyToAccount(k) });
const [admin, operator, brand] = KEYS.map((k) => wallet(k));

// World stub: accepts any proof unless it says deny; echoes the proof's nullifier
const world = createServer((req, res) => {
  let b = "";
  req.on("data", (c) => (b += c)).on("end", () => {
    const p = JSON.parse(b || "{}");
    res.writeHead(p.deny ? 400 : 200, { "content-type": "application/json" });
    res.end(JSON.stringify(p.deny ? { success: false, code: "invalid_proof" } : { success: true, nullifier: p.nullifier, action: "register-pet" }));
  });
}).listen(WORLD_PORT);

const art = JSON.parse(readFileSync(new URL("../../../contracts/out/CampaignVault.sol/CampaignVault.json", import.meta.url), "utf8"));
const deployTx = await admin.deployContract({ abi: art.abi, bytecode: art.bytecode.object, args: [operator.account.address] });
const vault = (await pub.waitForTransactionReceipt({ hash: deployTx })).contractAddress!;

const server = spawn(process.execPath, ["--import", "tsx", "src/index.ts"], {
  cwd: new URL("..", import.meta.url).pathname,
  stdio: "inherit",
  env: {
    ...process.env, PORT: "8799", WORKER: "off", HOLDBACK_HOURS: "0", STORE_PATH: join(mkdtempSync(join(tmpdir(), "notchi-e2e-")), "data.json"),
    ZG_CHAIN_ID: "31337", ZG_CHAIN_RPC: RPC, ZG_VAULT_ADDRESS: vault, ZG_VAULT_DEPLOY_BLOCK: "0", ZG_OPERATOR_KEY: KEYS[1],
    RP_ID: "rp_e2e", RP_SIGNING_KEY: KEYS[3].slice(2), WORLD_API_BASE: `http://127.0.0.1:${WORLD_PORT}`,
    MOOD_THRIVING_WEI: "1000", MOOD_STABLE_WEI: "100", MOOD_HUNGRY_WEI: "10",
  },
});
const call = async (path: string, body?: unknown) => {
  const r = await fetch(API + path, body === undefined ? {} : { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  return { status: r.status, json: (await r.json()) as any };
};

try {
  for (let i = 0; ; i++) {
    if (await fetch(`${API}/health`).then((r) => r.ok, () => false)) break;
    if (i > 60) throw new Error("server did not start");
    await new Promise((r) => setTimeout(r, 500));
  }

  const owner = privateKeyToAccount(generatePrivateKey()).address;
  const petKey = privateKeyToAccount(generatePrivateKey()).address;
  const payout = privateKeyToAccount(generatePrivateKey()).address;
  const reg = { petKey, ownerAddress: owner, payoutAddress: payout, name: "e2e-pet" };

  // denied: proof made for another wallet, then a proof World rejects
  let r = await call("/pets/register", { ...reg, worldProof: { signal_hash: signalHash(petKey), nullifier: "7" } });
  assert.equal(r.status, 403, JSON.stringify(r.json));
  assert.match(r.json.error, /different wallet/);
  r = await call("/pets/register", { ...reg, worldProof: { signal_hash: signalHash(owner), nullifier: "7", deny: true } });
  assert.equal(r.status, 403);
  assert.match(r.json.error, /World proof rejected: invalid_proof/);

  // registered onchain
  r = await call("/pets/register", { ...reg, worldProof: { signal_hash: signalHash(owner), nullifier: "7" } });
  assert.equal(r.status, 200, JSON.stringify(r.json));
  const [, , verified] = await pub.readContract({ address: vault, abi: parseAbi(["function pets(address) view returns (address, address, bool)"]), functionName: "pets", args: [petKey] });
  assert.equal(verified, true);
  // one human, one pet
  r = await call("/pets/register", { ...reg, petKey: privateKeyToAccount(generatePrivateKey()).address, name: "e2e-two", worldProof: { signal_hash: signalHash(owner), nullifier: "7" } });
  assert.equal(r.status, 409);

  // brand funds a campaign onchain, server records it
  const line = "Ship faster with Acme CI", rate = parseEther("0.001");
  const { timestamp } = await pub.getBlock();
  const vaultAbi = parseAbi(["function createCampaign(bytes32 lineHash, uint96 rate, uint64 endTime) payable returns (uint256)"]);
  const fundTx = await brand.writeContract({ address: vault, abi: vaultAbi, functionName: "createCampaign", args: [keccak256(toBytes(line)), rate, timestamp + 86400n], value: parseEther("1") });
  r = await call("/campaigns", { campaignId: "1", txHash: fundTx, hooks: [line], lineHash: keccak256(toBytes(line)), brand: "Acme" });
  assert.equal(r.status, 200, JSON.stringify(r.json));

  // a view that breaks the viewability rules is refused with the reason; a good one counts
  const view = { petKey: "e2e-pet", campaignId: "1", hook: 0, shownMs: 6000, unlocked: true, visible: true, idleS: 3 };
  r = await call("/impressions", { impressions: [{ ...view, unlocked: false }] });
  assert.equal(r.status, 400);
  assert.match(r.json.error, /locked/);
  r = await call("/impressions", { impressions: [view] });
  assert.equal(r.json.accepted, 1, JSON.stringify(r.json));

  // settle pays the pet's payout onchain
  r = await call("/settle/1", {});
  assert.equal(r.status, 200, JSON.stringify(r.json));
  assert.equal(r.json.count, 1);
  const receipt = await pub.getTransactionReceipt({ hash: r.json.txHash });
  assert.equal(receipt.status, "success");
  assert.equal(await pub.getBalance({ address: payout }), rate);

  r = await call("/campaigns/1/stats");
  assert.equal(r.json.views[0], 1);
  console.log("e2e: register, denied paths, fund, viewability, settle all passed");
} finally {
  server.kill();
  world.close();
}
