// Campaign vault on NEAR: a port of contracts/src/CampaignVault.sol (pause, admin handover and settleBatch left out)
// plus a per-pet compute budget. Brands lock a budget, the operator settles verified impressions to pets, a share
// of each payout funds the pet's compute budget, and the operator charges AI calls against it with the completion id.
// Amounts are yoctoNEAR (U128 in JSON), times are unix seconds. Every check runs before any state changes.
use near_sdk::json_types::U128;
use near_sdk::serde_json::json;
use near_sdk::store::{LookupMap, Vector};
use near_sdk::{env, near, require, AccountId, NearToken, PanicOnDefault, Promise};

pub const SETTLE_GRACE: u64 = 3600;
pub const DEFAULT_SHARE_BPS: u16 = 2000;
pub const MAX_SHARE_BPS: u16 = 5000;
pub const DEFAULT_DAILY_CAP: u128 = 20_000_000_000_000_000_000_000; // 0.02 NEAR
const DAY_NS: u64 = 86_400_000_000_000;

#[near(serializers = [json, borsh])]
#[derive(Clone)]
pub struct Campaign {
    pub brand: AccountId,
    pub budget: U128,
    pub spent: U128,
    pub rate: U128,
    pub end_time: u64,
    pub closed: bool,
    pub line_hash: String,
}

#[near(serializers = [json, borsh])]
#[derive(Clone)]
pub struct Pet {
    pub owner: AccountId,
    pub payout: AccountId,
    pub verified: bool,
    pub views: u64,
    pub earned: U128, // paid to the payout account
    pub compute_share_bps: u16,
    pub daily_cap: U128,
    pub compute_budget: U128,
    pub compute_spent: U128,
    pub charge_day: u64,
    pub charged_today: U128,
}

/// Running totals. Always: paid_to_pets + compute_budgets + compute_charged + remaining + refunded == total_deposited.
#[near(serializers = [json, borsh])]
#[derive(Clone, Default)]
pub struct Totals {
    pub total_deposited: U128,
    pub paid_to_pets: U128,
    pub compute_budgets: U128,
    pub compute_charged: U128,
    pub remaining: U128,
    pub refunded: U128,
}

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Vault {
    admin: AccountId,
    operator: AccountId,
    campaigns: Vector<Campaign>, // id = index + 1
    pets: LookupMap<String, Pet>,
    totals: Totals,
}

fn add(a: &mut U128, b: u128) {
    a.0 = a.0.checked_add(b).unwrap_or_else(|| env::panic_str("Overflow"));
}
fn sub(a: &mut U128, b: u128) {
    a.0 = a.0.checked_sub(b).unwrap_or_else(|| env::panic_str("Underflow"));
}
fn emit(event: &str, data: near_sdk::serde_json::Value) {
    let ev = json!({ "standard": "campaign_vault", "version": "1.0.0", "event": event, "data": [data] });
    env::log_str(&format!("EVENT_JSON:{ev}"));
}
fn now() -> u64 {
    env::block_timestamp() / 1_000_000_000
}
fn today() -> u64 {
    env::block_timestamp() / DAY_NS
}
fn pay(to: &AccountId, amount: u128) {
    if amount > 0 {
        let _ = Promise::new(to.clone()).transfer(NearToken::from_yoctonear(amount));
    }
}
fn valid_pet_id(id: &str) -> bool {
    (2..=64).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"-_.".contains(&b))
}
fn index(id: u64) -> Option<u32> {
    u32::try_from(id).ok()?.checked_sub(1)
}

#[near]
impl Vault {
    #[init]
    pub fn new(admin: AccountId, operator: AccountId) -> Self {
        Self { admin, operator, campaigns: Vector::new(b"c"), pets: LookupMap::new(b"p"), totals: Totals::default() }
    }

    // ---- admin and operator ----

    pub fn set_operator(&mut self, operator: AccountId) {
        require!(env::predecessor_account_id() == self.admin, "NotAdmin");
        self.operator = operator.clone();
        emit("operator_changed", json!({ "operator": operator }));
    }

    /// Operator registers a pet after the server's World ID check. Attach enough for storage; the rest is refunded.
    #[payable]
    pub fn register_pet(&mut self, pet_id: String, owner: AccountId, payout: AccountId) {
        self.only_operator();
        require!(valid_pet_id(&pet_id), "BadParams: pet_id must be 2-64 chars of a-z 0-9 - _ .");
        require!(!self.pets.contains_key(&pet_id), "BadParams: pet already registered");
        let before = env::storage_usage();
        let pet = Pet {
            owner: owner.clone(),
            payout: payout.clone(),
            verified: false,
            views: 0,
            earned: U128(0),
            compute_share_bps: DEFAULT_SHARE_BPS,
            daily_cap: U128(DEFAULT_DAILY_CAP),
            compute_budget: U128(0),
            compute_spent: U128(0),
            charge_day: 0,
            charged_today: U128(0),
        };
        self.pets.insert(pet_id.clone(), pet);
        self.pets.flush();
        let cost = env::storage_byte_cost().as_yoctonear() * u128::from(env::storage_usage() - before);
        let attached = env::attached_deposit().as_yoctonear();
        require!(attached >= cost, format!("NotEnoughStorageDeposit: attach at least {cost} yoctoNEAR"));
        pay(&env::predecessor_account_id(), attached - cost);
        emit("pet_registered", json!({ "pet_id": pet_id, "owner": owner, "payout": payout }));
    }

    pub fn set_verified(&mut self, pet_id: String, verified: bool) {
        self.only_operator();
        self.pet_mut(&pet_id).verified = verified;
        emit("pet_verified", json!({ "pet_id": pet_id, "verified": verified }));
    }

    // ---- pet owner ----

    pub fn set_payout(&mut self, pet_id: String, payout: AccountId) {
        self.pet_owner_mut(&pet_id).payout = payout.clone();
        emit("payout_changed", json!({ "pet_id": pet_id, "payout": payout }));
    }

    /// Share of each settlement that goes into the compute budget, in basis points, at most 50%.
    pub fn set_compute_share(&mut self, pet_id: String, bps: u16) {
        require!(bps <= MAX_SHARE_BPS, "BadParams: compute share is at most 5000 bps");
        self.pet_owner_mut(&pet_id).compute_share_bps = bps;
        emit("compute_share_set", json!({ "pet_id": pet_id, "bps": bps }));
    }

    pub fn set_compute_cap(&mut self, pet_id: String, daily_cap: U128) {
        self.pet_owner_mut(&pet_id).daily_cap = daily_cap;
        emit("compute_cap_set", json!({ "pet_id": pet_id, "daily_cap": daily_cap }));
    }

    // ---- brands ----

    /// Budget = attached deposit minus the storage this campaign uses.
    #[payable]
    pub fn create_campaign(&mut self, line_hash: String, rate: U128, end_time: u64) -> u64 {
        require!(line_hash.len() == 64 && line_hash.bytes().all(|b| b.is_ascii_hexdigit()), "BadParams: line_hash must be 64 hex chars");
        require!(rate.0 > 0 && end_time > now(), "BadParams: rate must be > 0 and end_time in the future");
        let brand = env::predecessor_account_id();
        let before = env::storage_usage();
        self.campaigns.push(Campaign { brand: brand.clone(), budget: U128(0), spent: U128(0), rate, end_time, closed: false, line_hash: line_hash.clone() });
        self.campaigns.flush();
        let cost = env::storage_byte_cost().as_yoctonear() * u128::from(env::storage_usage() - before);
        let budget = env::attached_deposit().as_yoctonear().saturating_sub(cost);
        require!(budget >= rate.0, format!("BadParams: deposit must cover storage ({cost} yoctoNEAR) plus at least one impression"));
        let id = self.campaigns.len();
        self.campaigns.get_mut(id - 1).unwrap().budget = U128(budget);
        add(&mut self.totals.total_deposited, budget);
        add(&mut self.totals.remaining, budget);
        emit("campaign_created", json!({ "id": id, "brand": brand, "budget": U128(budget), "rate": rate, "end_time": end_time, "line_hash": line_hash }));
        u64::from(id)
    }

    #[payable]
    pub fn top_up(&mut self, id: u64) {
        let amount = env::attached_deposit().as_yoctonear();
        let c = self.live(id);
        require!(env::predecessor_account_id() == c.brand, "NotBrand");
        require!(now() <= c.end_time, "CampaignEnded");
        require!(amount > 0, "BadParams: attach the top-up");
        let c = self.live_mut(id);
        add(&mut c.budget, amount);
        let budget = c.budget;
        add(&mut self.totals.total_deposited, amount);
        add(&mut self.totals.remaining, amount);
        emit("campaign_topped_up", json!({ "id": id, "amount": U128(amount), "budget": budget }));
    }

    /// Anyone may close after end + grace; the remainder goes back to the brand.
    pub fn close(&mut self, id: u64) {
        require!(now() > self.live(id).end_time + SETTLE_GRACE, "CampaignNotEnded");
        let c = self.live_mut(id);
        c.closed = true;
        let refund = c.budget.0 - c.spent.0;
        let brand = c.brand.clone();
        sub(&mut self.totals.remaining, refund);
        add(&mut self.totals.refunded, refund);
        pay(&brand, refund);
        emit("campaign_closed", json!({ "id": id, "refund": U128(refund) }));
    }

    // ---- operator: money out ----

    /// Pays a verified pet for `count` impressions; the compute share stays in the vault as its compute budget.
    pub fn settle_impressions(&mut self, id: u64, pet_id: String, count: u64) {
        self.only_operator();
        require!(count > 0, "BadParams: count must be > 0");
        let c = self.live(id);
        require!(now() <= c.end_time + SETTLE_GRACE, "CampaignEnded");
        let amount = c.rate.0.checked_mul(u128::from(count)).unwrap_or_else(|| env::panic_str("OverBudget"));
        require!(c.spent.0 + amount <= c.budget.0, "OverBudget");
        let pet = self.pets.get(&pet_id).unwrap_or_else(|| env::panic_str("UnknownPet"));
        require!(pet.verified, "PetNotVerified");
        let compute = amount * u128::from(pet.compute_share_bps) / 10_000;
        let paid = amount - compute;
        let payout = pet.payout.clone();

        add(&mut self.live_mut(id).spent, amount);
        let pet = self.pet_mut(&pet_id);
        pet.views += count;
        add(&mut pet.earned, paid);
        add(&mut pet.compute_budget, compute);
        sub(&mut self.totals.remaining, amount);
        add(&mut self.totals.paid_to_pets, paid);
        add(&mut self.totals.compute_budgets, compute);
        pay(&payout, paid);
        emit("impressions_settled", json!({ "id": id, "pet_id": pet_id, "payout": payout, "count": count, "amount": U128(amount), "paid": U128(paid), "compute": U128(compute) }));
    }

    /// Charges one AI call to the pet's compute budget and pays the operator, who holds the NEAR AI credits.
    pub fn charge_compute(&mut self, pet_id: String, amount: U128, near_ai_completion_id: String) {
        self.only_operator();
        require!(amount.0 > 0, "BadParams: amount must be > 0");
        require!((1..=128).contains(&near_ai_completion_id.len()), "BadParams: completion id must be 1-128 chars");
        let day = today();
        let pet = self.pets.get(&pet_id).unwrap_or_else(|| env::panic_str("UnknownPet"));
        let charged_today = if pet.charge_day == day { pet.charged_today.0 } else { 0 };
        require!(amount.0 <= pet.compute_budget.0, "OverComputeBudget");
        require!(charged_today + amount.0 <= pet.daily_cap.0, "OverDailyCap");

        let pet = self.pet_mut(&pet_id);
        pet.charge_day = day;
        pet.charged_today = U128(charged_today + amount.0);
        sub(&mut pet.compute_budget, amount.0);
        add(&mut pet.compute_spent, amount.0);
        let left = pet.compute_budget;
        sub(&mut self.totals.compute_budgets, amount.0);
        add(&mut self.totals.compute_charged, amount.0);
        pay(&self.operator, amount.0);
        emit("compute_charged", json!({ "pet_id": pet_id, "amount": amount, "near_ai_completion_id": near_ai_completion_id, "compute_budget": left }));
    }

    // ---- views ----

    pub fn get_admin(&self) -> AccountId {
        self.admin.clone()
    }
    pub fn get_operator(&self) -> AccountId {
        self.operator.clone()
    }
    pub fn get_campaign(&self, id: u64) -> Option<Campaign> {
        self.campaigns.get(index(id)?).cloned()
    }
    /// Campaigns from id `from` (1-based), at most `limit` (max 100), as (id, campaign).
    pub fn get_campaigns(&self, from: u64, limit: u64) -> Vec<(u64, Campaign)> {
        let from = from.max(1);
        (from..from.saturating_add(limit.min(100))).map_while(|id| self.get_campaign(id).map(|c| (id, c))).collect()
    }
    pub fn campaign_count(&self) -> u64 {
        u64::from(self.campaigns.len())
    }
    pub fn remaining(&self, id: u64) -> U128 {
        self.get_campaign(id).map_or(U128(0), |c| if c.closed { U128(0) } else { U128(c.budget.0 - c.spent.0) })
    }
    pub fn get_pet(&self, pet_id: String) -> Option<Pet> {
        self.pets.get(&pet_id).cloned()
    }
    pub fn compute_budget(&self, pet_id: String) -> U128 {
        self.pets.get(&pet_id).map_or(U128(0), |p| p.compute_budget)
    }
    pub fn compute_spent(&self, pet_id: String) -> U128 {
        self.pets.get(&pet_id).map_or(U128(0), |p| p.compute_spent)
    }
    pub fn charges_today(&self, pet_id: String) -> U128 {
        self.pets.get(&pet_id).map_or(U128(0), |p| if p.charge_day == today() { p.charged_today } else { U128(0) })
    }
    pub fn get_totals(&self) -> Totals {
        self.totals.clone()
    }

    // ---- internal ----

    fn only_operator(&self) {
        require!(env::predecessor_account_id() == self.operator, "NotOperator");
    }
    fn live(&self, id: u64) -> &Campaign {
        let c = index(id).and_then(|i| self.campaigns.get(i)).unwrap_or_else(|| env::panic_str("UnknownCampaign"));
        require!(!c.closed, "CampaignIsClosed");
        c
    }
    fn live_mut(&mut self, id: u64) -> &mut Campaign {
        index(id).and_then(|i| self.campaigns.get_mut(i)).unwrap_or_else(|| env::panic_str("UnknownCampaign"))
    }
    fn pet_mut(&mut self, pet_id: &String) -> &mut Pet {
        self.pets.get_mut(pet_id).unwrap_or_else(|| env::panic_str("UnknownPet"))
    }
    fn pet_owner_mut(&mut self, pet_id: &String) -> &mut Pet {
        let p = self.pet_mut(pet_id);
        require!(env::predecessor_account_id() == p.owner, "NotPetOwner");
        p
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    const NEAR: u128 = 1_000_000_000_000_000_000_000_000;

    fn ctx(who: &str, deposit: u128, now_s: u64) {
        testing_env!(VMContextBuilder::new()
            .predecessor_account_id(who.parse().unwrap())
            .attached_deposit(NearToken::from_yoctonear(deposit))
            .block_timestamp(now_s * 1_000_000_000)
            .account_balance(NearToken::from_near(1_000_000))
            .build());
    }

    /// xorshift64: deterministic, no extra dependency.
    struct Rng(u64);
    impl Rng {
        fn below(&mut self, n: u64) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0 % n
        }
    }

    fn check(v: &Vault) {
        let t = v.get_totals();
        let lhs = t.paid_to_pets.0 + t.compute_budgets.0 + t.compute_charged.0 + t.remaining.0 + t.refunded.0;
        assert_eq!(lhs, t.total_deposited.0, "paid + compute budgets + charged + remaining + refunded == deposited");
        let open: u128 = (1..=v.campaign_count()).map(|id| v.remaining(id).0).sum();
        assert_eq!(open, t.remaining.0, "remaining matches the open campaigns");
    }

    #[test]
    fn split_rounds_toward_the_payout() {
        ctx("op", 0, 1000);
        let mut v = Vault::new("admin".parse().unwrap(), "op".parse().unwrap());
        ctx("op", NEAR, 1000);
        v.register_pet("mochi".into(), "owner".parse().unwrap(), "payout".parse().unwrap());
        ctx("op", 0, 1000);
        v.set_verified("mochi".into(), true);
        ctx("brand", NEAR, 1000);
        let id = v.create_campaign("a".repeat(64), U128(7), 5000);
        ctx("op", 0, 1000);
        v.settle_impressions(id, "mochi".into(), 3); // 21 yocto: 20% is 4.2, so 4 to compute and 17 to the payout
        let p = v.get_pet("mochi".into()).unwrap();
        assert_eq!((p.compute_budget.0, p.earned.0, p.views), (4, 17, 3));
        check(&v);
    }

    #[test]
    fn daily_cap_resets_at_the_utc_day_boundary() {
        let day = 86_400u64;
        let t0 = 20_000 * day + day - 10; // 10 s before midnight UTC
        ctx("op", 0, t0);
        let mut v = Vault::new("admin".parse().unwrap(), "op".parse().unwrap());
        ctx("op", NEAR, t0);
        v.register_pet("mochi".into(), "owner".parse().unwrap(), "payout".parse().unwrap());
        ctx("op", 0, t0);
        v.set_verified("mochi".into(), true);
        ctx("brand", NEAR, t0);
        let id = v.create_campaign("a".repeat(64), U128(NEAR / 1_000), t0 + day);
        ctx("op", 0, t0);
        v.settle_impressions(id, "mochi".into(), 500); // 0.1 NEAR into the compute budget
        v.charge_compute("mochi".into(), U128(DEFAULT_DAILY_CAP), "chatcmpl-a".into());
        let over = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| v.charge_compute("mochi".into(), U128(1), "chatcmpl-b".into())));
        assert!(over.is_err(), "the cap holds for the rest of the day");
        ctx("op", 0, t0 + 11); // next UTC day
        assert_eq!(v.charges_today("mochi".into()).0, 0);
        v.charge_compute("mochi".into(), U128(DEFAULT_DAILY_CAP), "chatcmpl-c".into());
        assert_eq!(v.compute_spent("mochi".into()).0, 2 * DEFAULT_DAILY_CAP);
        check(&v);
    }

    /// Thousands of random operations, valid or refused; after each one the totals still add up.
    #[test]
    fn invariant_holds_under_random_operations() {
        let mut rng = Rng(0x9e37_79b9_7f4a_7c15);
        let mut t = 1_000u64;
        ctx("op", 0, t);
        let mut v = Vault::new("admin".parse().unwrap(), "op".parse().unwrap());
        let pets = ["p0", "p1", "p2"];
        for (i, p) in pets.iter().enumerate() {
            ctx("op", NEAR, t);
            v.register_pet((*p).into(), format!("owner{i}").parse().unwrap(), format!("pay{i}").parse().unwrap());
            ctx("op", 0, t);
            v.set_verified((*p).into(), i != 2); // p2 stays unverified
        }
        let (mut ok, mut refused) = (0, 0);
        for _ in 0..5_000 {
            t += rng.below(400);
            let k = rng.below(3) as usize;
            let pet = pets[k].to_string();
            let id = 1 + rng.below(v.campaign_count() + 1); // sometimes an unknown id
            let op = rng.below(7);
            let a = rng.below(1_000);
            let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| match op {
                0 => {
                    ctx("brand", NEAR / 100 + u128::from(a) * NEAR / 1_000, t);
                    v.create_campaign("b".repeat(64), U128(u128::from(1 + a) * NEAR / 100_000), t + 1 + a * 3);
                }
                1 => {
                    ctx("brand", u128::from(a) * NEAR / 10_000, t);
                    v.top_up(id);
                }
                2 | 3 => {
                    ctx("op", 0, t);
                    v.settle_impressions(id, pet.clone(), a % 50);
                }
                4 => {
                    ctx("op", 0, t);
                    v.charge_compute(pet.clone(), U128(u128::from(1 + a) * NEAR / 1_000_000), "chatcmpl-x".into());
                }
                5 => {
                    ctx("op", 0, t);
                    v.close(id);
                }
                _ => {
                    ctx(&format!("owner{k}"), 0, t);
                    v.set_compute_share(pet.clone(), (a * 6) as u16);
                }
            }));
            if r.is_ok() { ok += 1 } else { refused += 1 }
            check(&v);
        }
        let totals = v.get_totals();
        assert!(ok > 1_000 && refused > 500, "both paths exercised: {ok} ok, {refused} refused");
        assert!(totals.compute_charged.0 > 0 && totals.refunded.0 > 0 && totals.paid_to_pets.0 > 0);
    }
}
