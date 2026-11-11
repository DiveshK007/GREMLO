// Integration tests on a local NEAR sandbox: the real wasm, real accounts, real transfers.
use near_workspaces::network::Sandbox;
use near_workspaces::result::ExecutionFinalResult;
use near_workspaces::types::NearToken;
use near_workspaces::{Account, Contract, Worker};
use serde_json::{json, Value};

const NEAR: u128 = 1_000_000_000_000_000_000_000_000;
const MILLI: u128 = NEAR / 1_000;
const HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

struct T {
    worker: Worker<Sandbox>,
    vault: Contract,
    admin: Account,
    op: Account,
    brand: Account,
    owner: Account,
    payout: Account,
    stranger: Account,
}

async fn setup() -> anyhow::Result<T> {
    let worker = near_workspaces::sandbox().await?;
    let wasm = near_workspaces::compile_project("./").await?;
    let vault = worker.dev_deploy(&wasm).await?;
    let root = worker.root_account()?;
    let mut acc = vec![];
    for name in ["admin", "op", "brand", "owner", "payout", "stranger"] {
        acc.push(root.create_subaccount(name).initial_balance(NearToken::from_near(100)).transact().await?.into_result()?);
    }
    let [admin, op, brand, owner, payout, stranger]: [Account; 6] = acc.try_into().unwrap();
    vault.call("new").args_json(json!({ "admin": admin.id(), "operator": op.id() })).transact().await?.into_result()?;
    Ok(T { worker, vault, admin, op, brand, owner, payout, stranger })
}

impl T {
    async fn now(&self) -> anyhow::Result<u64> {
        Ok(self.worker.view_block().await?.timestamp() / 1_000_000_000)
    }
    async fn call(&self, who: &Account, method: &str, args: Value, deposit: u128) -> anyhow::Result<ExecutionFinalResult> {
        Ok(who.call(self.vault.id(), method).args_json(args).deposit(NearToken::from_yoctonear(deposit)).max_gas().transact().await?)
    }
    /// Succeeds or panics with the failure; returns the logs.
    async fn ok(&self, who: &Account, method: &str, args: Value, deposit: u128) -> anyhow::Result<Vec<String>> {
        let r = self.call(who, method, args, deposit).await?;
        let logs = r.logs().iter().map(|l| l.to_string()).collect();
        if let Err(e) = r.into_result() {
            panic!("{method} failed: {e:?}");
        }
        Ok(logs)
    }
    async fn fails(&self, who: &Account, method: &str, args: Value, deposit: u128, why: &str) -> anyhow::Result<()> {
        let r = self.call(who, method, args, deposit).await?;
        let err = format!("{:?}", r.into_result().expect_err(&format!("{method} should fail with {why}")));
        assert!(err.contains(why), "{method}: expected {why}, got {err}");
        Ok(())
    }
    async fn view(&self, method: &str, args: Value) -> anyhow::Result<Value> {
        Ok(self.vault.view(method).args_json(args).await?.json()?)
    }
    async fn balance(&self, a: &Account) -> anyhow::Result<u128> {
        Ok(a.view_account().await?.balance.as_yoctonear())
    }
    /// Registers and verifies pet "mochi", then creates a campaign: 1 NEAR, 1 milliNEAR per view, ends in an hour.
    async fn ready(&self) -> anyhow::Result<u64> {
        self.ok(&self.op, "register_pet", json!({ "pet_id": "mochi", "owner": self.owner.id(), "payout": self.payout.id() }), NEAR / 10).await?;
        self.ok(&self.op, "set_verified", json!({ "pet_id": "mochi", "verified": true }), 0).await?;
        self.create(NEAR, MILLI, 3600).await
    }
    async fn create(&self, deposit: u128, rate: u128, ends_in: u64) -> anyhow::Result<u64> {
        let end = self.now().await? + ends_in;
        let r = self.call(&self.brand, "create_campaign", json!({ "line_hash": HASH, "rate": rate.to_string(), "end_time": end }), deposit).await?;
        Ok(r.into_result().map_err(|e| anyhow::anyhow!("create_campaign failed: {e:?}"))?.json::<u64>()?)
    }
    async fn pet(&self) -> anyhow::Result<Value> {
        self.view("get_pet", json!({ "pet_id": "mochi" })).await
    }
}

fn n(v: &Value) -> u128 {
    v.as_str().map(|s| s.parse().unwrap()).unwrap_or_else(|| v.as_u64().unwrap() as u128)
}

async fn assert_invariant(t: &T) -> anyhow::Result<()> {
    let x = t.view("get_totals", json!({})).await?;
    let lhs = n(&x["paid_to_pets"]) + n(&x["compute_budgets"]) + n(&x["compute_charged"]) + n(&x["remaining"]) + n(&x["refunded"]);
    assert_eq!(lhs, n(&x["total_deposited"]), "paid + compute budgets + charged + remaining + refunded == deposited: {x}");
    let count = t.view("campaign_count", json!({})).await?.as_u64().unwrap();
    let mut open = 0;
    for id in 1..=count {
        open += n(&t.view("remaining", json!({ "id": id })).await?);
    }
    assert_eq!(open, n(&x["remaining"]));
    // the vault really holds what it owes: open budgets plus compute budgets
    assert!(t.balance(t.vault.as_account()).await? >= n(&x["remaining"]) + n(&x["compute_budgets"]));
    Ok(())
}

#[tokio::test]
async fn init_sets_admin_and_operator() -> anyhow::Result<()> {
    let t = setup().await?;
    assert_eq!(t.view("get_admin", json!({})).await?, json!(t.admin.id()));
    assert_eq!(t.view("get_operator", json!({})).await?, json!(t.op.id()));
    t.fails(&t.stranger, "new", json!({ "admin": t.admin.id(), "operator": t.op.id() }), 0, "already").await?;
    Ok(())
}

#[tokio::test]
async fn create_locks_budget_minus_storage() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.create(NEAR, MILLI, 3600).await?;
    assert_eq!(id, 1);
    let c = t.view("get_campaign", json!({ "id": 1 })).await?;
    let budget = n(&c["budget"]);
    assert!(budget < NEAR && budget > NEAR - NEAR / 100, "budget is the deposit minus a small storage cost: {budget}");
    assert_eq!(c["brand"], json!(t.brand.id()));
    assert_eq!(n(&t.view("remaining", json!({ "id": 1 })).await?), budget);
    assert_eq!(n(&t.view("get_totals", json!({})).await?["total_deposited"]), budget);
    assert_invariant(&t).await
}

#[tokio::test]
async fn create_rejects_bad_params() -> anyhow::Result<()> {
    let t = setup().await?;
    let end = t.now().await? + 3600;
    let call = |hash: &str, rate: u128, end: u64| json!({ "line_hash": hash, "rate": rate.to_string(), "end_time": end });
    t.fails(&t.brand, "create_campaign", call("abc", MILLI, end), NEAR, "line_hash").await?;
    t.fails(&t.brand, "create_campaign", call(&"g".repeat(64), MILLI, end), NEAR, "line_hash").await?;
    t.fails(&t.brand, "create_campaign", call(HASH, 0, end), NEAR, "rate must be > 0").await?;
    t.fails(&t.brand, "create_campaign", call(HASH, MILLI, end - 7200), NEAR, "end_time in the future").await?;
    t.fails(&t.brand, "create_campaign", call(HASH, NEAR, end), NEAR, "deposit must cover storage").await?;
    t.fails(&t.brand, "create_campaign", call(HASH, MILLI, end), 0, "deposit must cover storage").await?;
    assert_eq!(t.view("campaign_count", json!({})).await?, json!(0));
    Ok(())
}

#[tokio::test]
async fn top_up_by_brand_only() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.create(NEAR, MILLI, 3600).await?;
    let before = n(&t.view("remaining", json!({ "id": id })).await?);
    t.fails(&t.stranger, "top_up", json!({ "id": id }), NEAR, "NotBrand").await?;
    t.fails(&t.brand, "top_up", json!({ "id": id }), 0, "attach the top-up").await?;
    t.fails(&t.brand, "top_up", json!({ "id": 9 }), NEAR, "UnknownCampaign").await?;
    t.ok(&t.brand, "top_up", json!({ "id": id }), NEAR / 2).await?;
    assert_eq!(n(&t.view("remaining", json!({ "id": id })).await?), before + NEAR / 2);
    assert_invariant(&t).await
}

#[tokio::test]
async fn register_pet_operator_only_once_with_storage() -> anyhow::Result<()> {
    let t = setup().await?;
    let args = json!({ "pet_id": "mochi", "owner": t.owner.id(), "payout": t.payout.id() });
    t.fails(&t.stranger, "register_pet", args.clone(), NEAR / 10, "NotOperator").await?;
    t.fails(&t.op, "register_pet", args.clone(), 0, "NotEnoughStorageDeposit").await?;
    t.fails(&t.op, "register_pet", json!({ "pet_id": "Mochi!", "owner": t.owner.id(), "payout": t.payout.id() }), NEAR / 10, "pet_id must be").await?;
    let before = t.balance(&t.op).await?;
    t.ok(&t.op, "register_pet", args.clone(), NEAR).await?;
    assert!(before - t.balance(&t.op).await? < NEAR / 50, "the unused storage deposit is refunded");
    t.fails(&t.op, "register_pet", args, NEAR / 10, "already registered").await?;
    let p = t.pet().await?;
    assert_eq!((p["verified"].clone(), p["compute_share_bps"].clone()), (json!(false), json!(2000)));
    assert_eq!(n(&p["daily_cap"]), 20 * MILLI);
    Ok(())
}

#[tokio::test]
async fn set_verified_operator_only() -> anyhow::Result<()> {
    let t = setup().await?;
    t.ok(&t.op, "register_pet", json!({ "pet_id": "mochi", "owner": t.owner.id(), "payout": t.payout.id() }), NEAR / 10).await?;
    t.fails(&t.owner, "set_verified", json!({ "pet_id": "mochi", "verified": true }), 0, "NotOperator").await?;
    t.fails(&t.op, "set_verified", json!({ "pet_id": "nobody", "verified": true }), 0, "UnknownPet").await?;
    t.ok(&t.op, "set_verified", json!({ "pet_id": "mochi", "verified": true }), 0).await?;
    assert_eq!(t.pet().await?["verified"], json!(true));
    Ok(())
}

#[tokio::test]
async fn settle_pays_payout_and_funds_compute() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    let before = t.balance(&t.payout).await?;
    let r = t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 10 }), 0).await?;
    assert_eq!(t.balance(&t.payout).await? - before, 8 * MILLI, "80% of 10 views at 1 milliNEAR lands in the payout account");
    let p = t.pet().await?;
    assert_eq!((n(&p["compute_budget"]), n(&p["earned"]), p["views"].as_u64()), (2 * MILLI, 8 * MILLI, Some(10)));
    assert_eq!(n(&t.view("compute_budget", json!({ "pet_id": "mochi" })).await?), 2 * MILLI);
    assert!(r.iter().any(|l| l.starts_with("EVENT_JSON:") && l.contains("\"impressions_settled\"")));
    assert_invariant(&t).await
}

#[tokio::test]
async fn settle_up_to_exact_budget_then_over_budget_reverts() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    let rate = MILLI;
    let exact = n(&t.view("get_campaign", json!({ "id": id })).await?["budget"]) / rate;
    t.fails(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": u64::MAX }), 0, "OverBudget").await?;
    t.fails(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": exact + 1 }), 0, "OverBudget").await?;
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": exact }), 0).await?;
    t.fails(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 1 }), 0, "OverBudget").await?;
    assert!(n(&t.view("remaining", json!({ "id": id })).await?) < rate);
    assert_invariant(&t).await
}

#[tokio::test]
async fn settle_refusals() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    t.ok(&t.op, "register_pet", json!({ "pet_id": "unverified", "owner": t.owner.id(), "payout": t.payout.id() }), NEAR / 10).await?;
    let s = |id: u64, pet: &str, count: u64| json!({ "id": id, "pet_id": pet, "count": count });
    t.fails(&t.stranger, "settle_impressions", s(id, "mochi", 1), 0, "NotOperator").await?;
    t.fails(&t.brand, "settle_impressions", s(id, "mochi", 1), 0, "NotOperator").await?;
    t.fails(&t.op, "settle_impressions", s(id, "unverified", 1), 0, "PetNotVerified").await?;
    t.fails(&t.op, "settle_impressions", s(id, "nobody", 1), 0, "UnknownPet").await?;
    t.fails(&t.op, "settle_impressions", s(99, "mochi", 1), 0, "UnknownCampaign").await?;
    t.fails(&t.op, "settle_impressions", s(0, "mochi", 1), 0, "UnknownCampaign").await?;
    t.fails(&t.op, "settle_impressions", s(id, "mochi", 0), 0, "count must be > 0").await?;
    assert_eq!(t.pet().await?["views"], json!(0));
    assert_invariant(&t).await
}

#[tokio::test]
async fn only_the_owner_changes_payout() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    let args = json!({ "pet_id": "mochi", "payout": t.stranger.id() });
    t.fails(&t.op, "set_payout", args.clone(), 0, "NotPetOwner").await?;
    t.fails(&t.payout, "set_payout", args.clone(), 0, "NotPetOwner").await?;
    t.fails(&t.admin, "set_payout", args.clone(), 0, "NotPetOwner").await?;
    t.ok(&t.owner, "set_payout", args, 0).await?;
    let before = t.balance(&t.stranger).await?;
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 5 }), 0).await?;
    assert_eq!(t.balance(&t.stranger).await? - before, 4 * MILLI, "the new payout account is paid");
    Ok(())
}

#[tokio::test]
async fn compute_share_owner_only_and_capped() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    t.fails(&t.op, "set_compute_share", json!({ "pet_id": "mochi", "bps": 1000 }), 0, "NotPetOwner").await?;
    t.fails(&t.owner, "set_compute_share", json!({ "pet_id": "mochi", "bps": 5001 }), 0, "at most 5000").await?;
    t.ok(&t.owner, "set_compute_share", json!({ "pet_id": "mochi", "bps": 0 }), 0).await?;
    let before = t.balance(&t.payout).await?;
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 3 }), 0).await?;
    assert_eq!(t.balance(&t.payout).await? - before, 3 * MILLI, "a 0% share pays everything out");
    t.ok(&t.owner, "set_compute_share", json!({ "pet_id": "mochi", "bps": 5000 }), 0).await?;
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 4 }), 0).await?;
    assert_eq!(n(&t.pet().await?["compute_budget"]), 2 * MILLI);
    assert_invariant(&t).await
}

#[tokio::test]
async fn charge_compute_pays_operator_and_logs_the_completion_id() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 10 }), 0).await?; // 2 milli to compute
    let before = t.balance(&t.op).await?;
    let r = t.ok(&t.op, "charge_compute", json!({ "pet_id": "mochi", "amount": (MILLI / 2).to_string(), "near_ai_completion_id": "chatcmpl-abc123" }), 0).await?;
    let log = r.iter().find(|l| l.contains("compute_charged")).expect("compute_charged event");
    let ev: Value = serde_json::from_str(log.strip_prefix("EVENT_JSON:").unwrap())?;
    assert_eq!((ev["standard"].clone(), ev["version"].clone()), (json!("campaign_vault"), json!("1.0.0")));
    assert_eq!(ev["data"][0]["near_ai_completion_id"], json!("chatcmpl-abc123"));
    // the operator paid gas for this tx, so it received the charge minus a small fee
    let gained = t.balance(&t.op).await? as i128 - before as i128;
    assert!(gained > (MILLI / 2) as i128 - (MILLI / 2) as i128 / 2 && gained <= (MILLI / 2) as i128, "operator gained {gained}");
    assert_eq!(n(&t.view("compute_budget", json!({ "pet_id": "mochi" })).await?), MILLI * 3 / 2);
    assert_eq!(n(&t.view("compute_spent", json!({ "pet_id": "mochi" })).await?), MILLI / 2);
    assert_eq!(n(&t.view("charges_today", json!({ "pet_id": "mochi" })).await?), MILLI / 2);
    assert_invariant(&t).await
}

#[tokio::test]
async fn charge_compute_refusals() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    let c = |amount: u128, cid: &str| json!({ "pet_id": "mochi", "amount": amount.to_string(), "near_ai_completion_id": cid });
    t.fails(&t.op, "charge_compute", c(1, "x"), 0, "OverComputeBudget").await?; // empty budget: zero floor
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 10 }), 0).await?;
    t.fails(&t.stranger, "charge_compute", c(1, "x"), 0, "NotOperator").await?;
    t.fails(&t.owner, "charge_compute", c(1, "x"), 0, "NotOperator").await?;
    t.fails(&t.op, "charge_compute", c(0, "x"), 0, "amount must be > 0").await?;
    t.fails(&t.op, "charge_compute", c(1, ""), 0, "completion id").await?;
    t.fails(&t.op, "charge_compute", c(1, &"x".repeat(129)), 0, "completion id").await?;
    t.fails(&t.op, "charge_compute", c(2 * MILLI + 1, "x"), 0, "OverComputeBudget").await?;
    t.fails(&t.op, "charge_compute", json!({ "pet_id": "nobody", "amount": "1", "near_ai_completion_id": "x" }), 0, "UnknownPet").await?;
    t.ok(&t.op, "charge_compute", c(2 * MILLI, "x"), 0).await?; // down to exactly zero
    t.fails(&t.op, "charge_compute", c(1, "x"), 0, "OverComputeBudget").await?;
    assert_eq!(n(&t.view("compute_budget", json!({ "pet_id": "mochi" })).await?), 0);
    assert_invariant(&t).await
}

#[tokio::test]
async fn daily_cap_is_owner_set_and_enforced() -> anyhow::Result<()> {
    let t = setup().await?;
    let id = t.ready().await?;
    t.ok(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": 500 }), 0).await?; // 100 milli to compute
    let c = |amount: u128| json!({ "pet_id": "mochi", "amount": amount.to_string(), "near_ai_completion_id": "chatcmpl-1" });
    t.ok(&t.op, "charge_compute", c(15 * MILLI), 0).await?;
    t.fails(&t.op, "charge_compute", c(5 * MILLI + 1), 0, "OverDailyCap").await?; // default cap 20 milli a day
    t.ok(&t.op, "charge_compute", c(5 * MILLI), 0).await?;
    t.fails(&t.op, "set_compute_cap", json!({ "pet_id": "mochi", "daily_cap": (50 * MILLI).to_string() }), 0, "NotPetOwner").await?;
    t.ok(&t.owner, "set_compute_cap", json!({ "pet_id": "mochi", "daily_cap": (50 * MILLI).to_string() }), 0).await?;
    t.ok(&t.op, "charge_compute", c(30 * MILLI), 0).await?;
    t.fails(&t.op, "charge_compute", c(1), 0, "OverDailyCap").await?;
    assert_eq!(n(&t.view("charges_today", json!({ "pet_id": "mochi" })).await?), 50 * MILLI);
    assert_invariant(&t).await
}

#[tokio::test]
async fn set_operator_admin_only() -> anyhow::Result<()> {
    let t = setup().await?;
    t.fails(&t.op, "set_operator", json!({ "operator": t.stranger.id() }), 0, "NotAdmin").await?;
    t.ok(&t.admin, "set_operator", json!({ "operator": t.stranger.id() }), 0).await?;
    let args = json!({ "pet_id": "mochi", "owner": t.owner.id(), "payout": t.payout.id() });
    t.fails(&t.op, "register_pet", args.clone(), NEAR / 10, "NotOperator").await?;
    t.ok(&t.stranger, "register_pet", args, NEAR / 10).await?;
    Ok(())
}

#[tokio::test]
async fn get_campaigns_pages_by_id() -> anyhow::Result<()> {
    let t = setup().await?;
    for _ in 0..3 {
        t.create(NEAR / 10, MILLI, 3600).await?;
    }
    let ids = |v: Value| v.as_array().unwrap().iter().map(|p| p[0].as_u64().unwrap()).collect::<Vec<_>>();
    assert_eq!(ids(t.view("get_campaigns", json!({ "from": 1, "limit": 10 })).await?), vec![1, 2, 3]);
    assert_eq!(ids(t.view("get_campaigns", json!({ "from": 2, "limit": 1 })).await?), vec![2]);
    assert_eq!(ids(t.view("get_campaigns", json!({ "from": 4, "limit": 10 })).await?), Vec::<u64>::new());
    assert_eq!(t.view("get_campaign", json!({ "id": 0 })).await?, Value::Null);
    Ok(())
}

/// The time rules: no top-up after the end, settling allowed through the 1h grace, close only after it.
#[tokio::test]
async fn end_grace_close_and_refund() -> anyhow::Result<()> {
    let t = setup().await?;
    t.ok(&t.op, "register_pet", json!({ "pet_id": "mochi", "owner": t.owner.id(), "payout": t.payout.id() }), NEAR / 10).await?;
    t.ok(&t.op, "set_verified", json!({ "pet_id": "mochi", "verified": true }), 0).await?;
    let id = t.create(NEAR, MILLI, 20).await?;
    let s = json!({ "id": id, "pet_id": "mochi", "count": 1 });
    t.ok(&t.op, "settle_impressions", s.clone(), 0).await?;
    let end = n(&t.view("get_campaign", json!({ "id": id })).await?["end_time"]) as u64;
    while t.now().await? <= end {
        t.worker.fast_forward(20).await?;
    }
    t.fails(&t.brand, "top_up", json!({ "id": id }), NEAR, "CampaignEnded").await?;
    t.ok(&t.op, "settle_impressions", s.clone(), 0).await?; // inside the grace window
    t.fails(&t.stranger, "close", json!({ "id": id }), 0, "CampaignNotEnded").await?;
    while t.now().await? <= end + 3600 {
        t.worker.fast_forward(500).await?;
    }
    t.fails(&t.op, "settle_impressions", s.clone(), 0, "CampaignEnded").await?;
    let left = n(&t.view("remaining", json!({ "id": id })).await?);
    let before = t.balance(&t.brand).await?;
    t.ok(&t.stranger, "close", json!({ "id": id }), 0).await?; // anyone may close; the refund goes to the brand
    assert_eq!(t.balance(&t.brand).await? - before, left);
    assert_eq!(n(&t.view("remaining", json!({ "id": id })).await?), 0);
    t.fails(&t.stranger, "close", json!({ "id": id }), 0, "CampaignIsClosed").await?;
    t.fails(&t.op, "settle_impressions", s, 0, "CampaignIsClosed").await?;
    t.fails(&t.brand, "top_up", json!({ "id": id }), NEAR, "CampaignIsClosed").await?;
    assert_invariant(&t).await
}

/// Random valid and invalid calls against the real contract; after each one the totals add up and the vault
/// holds at least what it owes.
#[tokio::test]
async fn random_operations_keep_the_invariant() -> anyhow::Result<()> {
    let t = setup().await?;
    t.ready().await?;
    let mut x: u64 = 0x2545_f491_4f6c_dd1d;
    let mut rnd = |m: u64| {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        x % m
    };
    for _ in 0..40 {
        let count = t.view("campaign_count", json!({})).await?.as_u64().unwrap();
        let id = 1 + rnd(count + 1);
        let a = rnd(1_000) as u128;
        let r = match rnd(6) {
            0 => t.call(&t.brand, "create_campaign", json!({ "line_hash": HASH, "rate": (MILLI * (1 + a % 5)).to_string(), "end_time": t.now().await? + 3600 }), NEAR / 20 + a * MILLI / 10).await?,
            1 => t.call(&t.brand, "top_up", json!({ "id": id }), a * MILLI / 10).await?,
            2 | 3 => t.call(&t.op, "settle_impressions", json!({ "id": id, "pet_id": "mochi", "count": a % 80 }), 0).await?,
            4 => t.call(&t.op, "charge_compute", json!({ "pet_id": "mochi", "amount": (a * MILLI / 100 + 1).to_string(), "near_ai_completion_id": "chatcmpl-r" }), 0).await?,
            _ => t.call(&t.owner, "set_compute_share", json!({ "pet_id": "mochi", "bps": a * 6 }), 0).await?,
        };
        let _ = r.into_result(); // refusals are expected here
        assert_invariant(&t).await?;
    }
    let x = t.view("get_totals", json!({})).await?;
    assert!(n(&x["paid_to_pets"]) > 0 && n(&x["compute_charged"]) > 0, "the run settled and charged: {x}");
    Ok(())
}
