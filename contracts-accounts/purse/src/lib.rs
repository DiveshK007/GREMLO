// A pet's purse (1.0 design, R4 §18): deployed to `<pet>.<parent>` by the factory. The owner's wallet holds the
// account's full-access key; the Mac holds only a function-call key limited to `pay_inference`, which can't move
// funds by itself. Every spend goes through here: an allow-list of inference providers, a per-call cap and a daily
// cap. The model can ask for a payment; it can never sign one. Amounts are yoctoNEAR (U128 in JSON).
use near_sdk::json_types::U128;
use near_sdk::serde_json::json;
use near_sdk::{env, near, require, AccountId, NearToken, PanicOnDefault, Promise};

const DAY_NS: u64 = 86_400_000_000_000;
/// Kept back for the purse's own storage; never spent or withdrawn.
pub const RESERVE: u128 = 500_000_000_000_000_000_000_000; // 0.5 NEAR

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Purse {
    owner: AccountId,
    providers: Vec<AccountId>,
    per_call: u128,
    daily: u128,
    spent_today: u128,
    day: u64,
    total_paid: u128,
}

#[near(serializers = [json])]
pub struct PurseView {
    pub owner: AccountId,
    pub providers: Vec<AccountId>,
    pub per_call: U128,
    pub daily: U128,
    pub spent_today: U128,
    pub total_paid: U128,
}

#[near]
impl Purse {
    #[init]
    pub fn new(owner: AccountId, providers: Vec<AccountId>, per_call: U128, daily: U128) -> Self {
        require!(per_call.0 > 0 && per_call.0 <= daily.0, "per-call cap must be above zero and at most the daily cap");
        require!(providers.len() <= 10, "at most 10 providers");
        Self { owner, providers, per_call: per_call.0, daily: daily.0, spent_today: 0, day: env::block_timestamp() / DAY_NS, total_paid: 0 }
    }

    /// The one method the Mac's key may call. It can only pay an allow-listed provider, within both caps.
    pub fn pay_inference(&mut self, provider: AccountId, amount: U128, request_id: String) -> Promise {
        require!(env::predecessor_account_id() == env::current_account_id(), "only this purse's own keys can spend");
        require!(self.providers.contains(&provider), "provider is not on the allow-list");
        require!(!request_id.is_empty() && request_id.len() <= 128, "a request id is required");
        let a = amount.0;
        require!(a > 0 && a <= self.per_call, "over the per-call cap");
        let today = env::block_timestamp() / DAY_NS;
        if today != self.day { self.day = today; self.spent_today = 0; }
        require!(self.spent_today + a <= self.daily, "over the daily cap");
        require!(env::account_balance().as_yoctonear() >= a + Self::locked(), "not enough in the purse");
        self.spent_today += a;
        self.total_paid += a;
        env::log_str(&format!("EVENT_JSON:{}", json!({"standard": "notchi", "version": "1.0.0", "event": "paid_for_thinking",
            "data": {"provider": provider, "amount": amount, "request_id": request_id}})));
        Promise::new(provider).transfer(NearToken::from_yoctonear(a))
    }

    /// Owner only: the owner's account, or this account's full-access key (the Mac's key can't call this).
    pub fn set_caps(&mut self, per_call: U128, daily: U128) {
        self.only_owner();
        require!(per_call.0 > 0 && per_call.0 <= daily.0, "per-call cap must be above zero and at most the daily cap");
        self.per_call = per_call.0;
        self.daily = daily.0;
    }

    pub fn set_providers(&mut self, providers: Vec<AccountId>) {
        self.only_owner();
        require!(providers.len() <= 10, "at most 10 providers");
        self.providers = providers;
    }

    /// Owner only, to the owner unless told otherwise. The reserve stays.
    pub fn withdraw(&mut self, amount: U128, to: Option<AccountId>) -> Promise {
        self.only_owner();
        require!(env::account_balance().as_yoctonear() >= amount.0 + Self::locked(), "that would dip into the reserve");
        Promise::new(to.unwrap_or_else(|| self.owner.clone())).transfer(NearToken::from_yoctonear(amount.0))
    }

    pub fn get_purse(&self) -> PurseView {
        PurseView { owner: self.owner.clone(), providers: self.providers.clone(), per_call: U128(self.per_call), daily: U128(self.daily),
                    spent_today: U128(if env::block_timestamp() / DAY_NS == self.day { self.spent_today } else { 0 }), total_paid: U128(self.total_paid) }
    }

    /// What must stay: the storage stake for the code and state, plus the reserve.
    fn locked() -> u128 { env::storage_usage() as u128 * env::storage_byte_cost().as_yoctonear() + RESERVE }

    fn only_owner(&self) {
        let p = env::predecessor_account_id();
        require!(p == self.owner || p == env::current_account_id(), "owner only");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::{get_created_receipts, VMContextBuilder};
    use near_sdk::testing_env;

    const NEAR: u128 = 1_000_000_000_000_000_000_000_000;
    fn acc(s: &str) -> AccountId { s.parse().unwrap() }
    fn ctx(pred: &str, day: u64) {
        testing_env!(VMContextBuilder::new().current_account_id(acc("mochi.notchi.near")).predecessor_account_id(acc(pred))
            .account_balance(NearToken::from_yoctonear(2 * NEAR)).storage_usage(130_000).block_timestamp(day * DAY_NS + 1).build());
    }
    fn purse() -> Purse {
        ctx("notchi.near", 1);
        Purse::new(acc("owner.near"), vec![acc("ai.provider.near")], U128(NEAR / 100), U128(NEAR / 20))
    }

    #[test]
    fn pays_an_allow_listed_provider_within_caps() {
        let mut p = purse();
        ctx("mochi.notchi.near", 1);
        p.pay_inference(acc("ai.provider.near"), U128(NEAR / 100), "req-1".into());
        assert_eq!(p.get_purse().spent_today.0, NEAR / 100);
        assert!(get_created_receipts().iter().any(|r| r.receiver_id == acc("ai.provider.near")));
    }

    #[test]
    #[should_panic(expected = "only this purse's own keys")]
    fn nobody_else_can_spend() { let mut p = purse(); ctx("ai.provider.near", 1); p.pay_inference(acc("ai.provider.near"), U128(1), "r".into()); }

    #[test]
    #[should_panic(expected = "not on the allow-list")]
    fn only_allow_listed_providers() { let mut p = purse(); ctx("mochi.notchi.near", 1); p.pay_inference(acc("thief.near"), U128(1), "r".into()); }

    #[test]
    #[should_panic(expected = "over the per-call cap")]
    fn per_call_cap() { let mut p = purse(); ctx("mochi.notchi.near", 1); p.pay_inference(acc("ai.provider.near"), U128(NEAR / 100 + 1), "r".into()); }

    #[test]
    #[should_panic(expected = "over the daily cap")]
    fn the_call_that_crosses_the_daily_cap_is_rejected() {
        let mut p = purse();
        ctx("mochi.notchi.near", 1);
        for i in 0..5 { p.pay_inference(acc("ai.provider.near"), U128(NEAR / 100), format!("r{i}")); }
        p.pay_inference(acc("ai.provider.near"), U128(1), "r6".into());
    }

    #[test]
    fn the_daily_cap_resets_the_next_day() {
        let mut p = purse();
        ctx("mochi.notchi.near", 1);
        for i in 0..5 { p.pay_inference(acc("ai.provider.near"), U128(NEAR / 100), format!("r{i}")); }
        ctx("mochi.notchi.near", 2);
        p.pay_inference(acc("ai.provider.near"), U128(NEAR / 100), "next".into());
        assert_eq!(p.get_purse().spent_today.0, NEAR / 100);
    }

    #[test]
    #[should_panic(expected = "owner only")]
    fn a_provider_cant_withdraw() { let mut p = purse(); ctx("ai.provider.near", 1); p.withdraw(U128(1), None); }

    #[test]
    #[should_panic(expected = "reserve")]
    fn withdraw_keeps_the_reserve() { let mut p = purse(); ctx("owner.near", 1); p.withdraw(U128(2 * NEAR - RESERVE + 1), None); }

    #[test]
    #[should_panic(expected = "not enough in the purse")]
    fn the_storage_stake_is_never_spent() {
        let mut p = purse();
        testing_env!(VMContextBuilder::new().current_account_id(acc("mochi.notchi.near")).predecessor_account_id(acc("mochi.notchi.near"))
            .account_balance(NearToken::from_yoctonear(18 * NEAR / 10)).storage_usage(130_000).block_timestamp(DAY_NS + 1).build());
        p.pay_inference(acc("ai.provider.near"), U128(NEAR / 100), "r".into()); // 1.3 stake + 0.5 reserve leaves nothing to spend
    }

    #[test]
    #[should_panic(expected = "a request id is required")]
    fn a_payment_needs_a_request_id() { let mut p = purse(); ctx("mochi.notchi.near", 1); p.pay_inference(acc("ai.provider.near"), U128(1), String::new()); }
}
