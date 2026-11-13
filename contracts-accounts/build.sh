#!/usr/bin/env bash
# Builds the purse, embeds it in the factory, builds the factory. Needs cargo-near.
set -euo pipefail
cd "$(dirname "$0")"
(cd purse && cargo near build non-reproducible-wasm --no-abi)
mkdir -p res && cp target/near/gremlo_purse/gremlo_purse.wasm res/
(cd factory && cargo near build non-reproducible-wasm --no-abi)
cp target/near/gremlo_factory/gremlo_factory.wasm res/
ls -la res
