// The pet account factory (1.0 design, R4 §18), deployed to the parent account (`notchi.near`). Only a parent
// can create its sub-accounts, so this creates `<pet>.notchi.near` at hatching and deploys the purse to it. The
// owner's wallet gets the full-access key; the Mac gets a function-call key that can only call `pay_inference` on
// the purse. The factory keeps no key on the new account. No auctions, no paid names: a taken name is refunded
// with a suggestion.
use near_sdk::json_types::U128;
use near_sdk::serde_json::json;
use near_sdk::{env, near, require, AccountId, Allowance, Gas, NearToken, PanicOnDefault, Promise, PromiseError, PublicKey};

#[cfg(not(test))]
const PURSE_WASM: &[u8] = include_bytes!("../../res/notchi_purse.wasm");
#[cfg(test)]
const PURSE_WASM: &[u8] = b"\0asm-test-purse";

/// Storage for the purse code plus its reserve.
pub const MIN_DEPOSIT: u128 = 2_000_000_000_000_000_000_000_000; // 2 NEAR
/// Gas fees the Mac's key may burn on its own; spending still needs pay_inference and its caps.
pub const MAC_KEY_ALLOWANCE: u128 = 250_000_000_000_000_000_000_000; // 0.25 NEAR

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Factory {
    providers: Vec<AccountId>,
    per_call: u128,
    daily: u128,
}

#[near]
impl Factory {
    #[init]
    pub fn new(providers: Vec<AccountId>, per_call: U128, daily: U128) -> Self {
        Self { providers, per_call: per_call.0, daily: daily.0 }
    }

    #[payable]
    pub fn create_pet(&mut self, name: String, owner: AccountId, owner_key: PublicKey, mac_key: PublicKey) -> Promise {
        require!(Self::valid_name(&name), "a pet name is 2-32 of a-z, 0-9 and dashes");
        let deposit = env::attached_deposit().as_yoctonear();
        require!(deposit >= MIN_DEPOSIT, "attach at least 2 NEAR for the purse's storage and reserve");
        require!(owner_key != mac_key, "the Mac's key must not be the owner's key");
        let id: AccountId = format!("{}.{}", name, env::current_account_id()).parse().unwrap_or_else(|_| env::panic_str("bad account id"));
        let init = json!({"owner": owner, "providers": self.providers, "per_call": U128(self.per_call), "daily": U128(self.daily)}).to_string();
        Promise::new(id.clone())
            .create_account()
            .transfer(NearToken::from_yoctonear(deposit))
            .deploy_contract(PURSE_WASM.to_vec())
            .function_call("new", init.into_bytes(), NearToken::from_yoctonear(0), Gas::from_tgas(20))
            .add_full_access_key(owner_key)
            .add_access_key_allowance(mac_key, Allowance::limited(NearToken::from_yoctonear(MAC_KEY_ALLOWANCE)).unwrap(), id.clone(), "pay_inference")
            .then(Self::ext(env::current_account_id()).with_static_gas(Gas::from_tgas(10))
                .on_created(id, name, env::predecessor_account_id(), U128(deposit)))
    }

    /// A taken name (or any failure) refunds the deposit and suggests `<name>-2`.
    #[private]
    pub fn on_created(&mut self, id: AccountId, name: String, payer: AccountId, deposit: U128, #[callback_result] result: Result<(), PromiseError>) -> bool {
        if result.is_ok() {
            env::log_str(&format!("created {id}"));
            return true;
        }
        env::log_str(&format!("{id} could not be created (the name may be taken); try {name}-2. Deposit refunded."));
        Promise::new(payer).transfer(NearToken::from_yoctonear(deposit.0)).detach();
        false
    }
}

impl Factory {
    /// 2-32 of a-z, 0-9 and dashes, not starting or ending with a dash.
    pub fn valid_name(name: &str) -> bool {
        (2..=32).contains(&name.len()) && !name.starts_with('-') && !name.ends_with('-')
            && name.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::mock::MockAction;
    use near_sdk::test_utils::{get_created_receipts, VMContextBuilder};
    use near_sdk::testing_env;

    fn acc(s: &str) -> AccountId { s.parse().unwrap() }
    fn key(n: u8) -> PublicKey { format!("ed25519:{}", near_sdk::bs58::encode([n; 32]).into_string()).parse().unwrap() }
    fn ctx(deposit: u128) {
        testing_env!(VMContextBuilder::new().current_account_id(acc("notchi.near")).predecessor_account_id(acc("owner.near"))
            .attached_deposit(NearToken::from_yoctonear(deposit)).build());
    }
    fn factory() -> Factory { ctx(0); Factory::new(vec![acc("ai.provider.near")], U128(10), U128(100)) }

    #[test]
    fn names() {
        assert!(Factory::valid_name("mochi") && Factory::valid_name("mochi-2"));
        assert!(!Factory::valid_name("m") && !Factory::valid_name("-mochi") && !Factory::valid_name("Mochi") && !Factory::valid_name("mo.chi"));
    }

    #[test]
    fn the_macs_key_can_only_call_pay_inference_and_the_owner_holds_full_access() {
        let mut f = factory();
        ctx(MIN_DEPOSIT);
        f.create_pet("mochi".into(), acc("owner.near"), key(1), key(2)).detach();
        let r = get_created_receipts();
        let pet = r.iter().find(|r| r.receiver_id == acc("mochi.notchi.near")).expect("a receipt for the new account");
        let mut fc = None;
        let mut full = 0;
        for a in &pet.actions {
            match a {
                MockAction::AddKeyWithFunctionCall { receiver_id, method_names, allowance, .. } => fc = Some((receiver_id.clone(), method_names.clone(), *allowance)),
                MockAction::AddKeyWithFullAccess { .. } => full += 1,
                _ => {}
            }
        }
        let (receiver, methods, allowance) = fc.expect("the Mac's function-call key");
        assert_eq!(receiver, acc("mochi.notchi.near"));
        assert_eq!(methods, vec!["pay_inference".to_string()]);
        assert_eq!(allowance, Some(NearToken::from_yoctonear(MAC_KEY_ALLOWANCE)));
        assert_eq!(full, 1, "exactly one full-access key: the owner's; the factory keeps none");
        assert!(pet.actions.iter().any(|a| matches!(a, MockAction::DeployContract { .. })));
        assert!(pet.actions.iter().any(|a| matches!(a, MockAction::CreateAccount { .. })));
    }

    #[test]
    #[should_panic(expected = "attach at least 2 NEAR")]
    fn needs_the_deposit() { let mut f = factory(); ctx(1); f.create_pet("mochi".into(), acc("owner.near"), key(1), key(2)).detach(); }

    #[test]
    #[should_panic(expected = "must not be the owner's key")]
    fn separate_keys() { let mut f = factory(); ctx(MIN_DEPOSIT); f.create_pet("mochi".into(), acc("owner.near"), key(1), key(1)).detach(); }
}
