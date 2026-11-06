# World ID integration debrief

## What we used it for

One human, one pet. Notchi pays pets per ad impression, so the obvious attack is running many fake pets. A pet is only registered onchain (and only paid) after a World ID proof, and each human can register once.

## Flow

1. Web app asks our server for a signed request: `GET /world/sign?action=register-pet`. The server signs with `signRequest` from `@worldcoin/idkit-core/signing`. The RP signing key never leaves the server.
2. Web app calls `IDKit.request({ app_id, action, rp_context, allow_legacy_proofs: false, environment })`, shows the `connectorURI` as a QR code and polls with `pollUntilCompletion`.
3. The result goes to `POST /pets/register`. The server forwards it unchanged to `https://developer.worldcoin.org/api/v4/verify/{RP_ID}` and trusts the `success` field.
4. The server stores the nullifier, then calls `registerPet` on the CampaignVault contract. A reused nullifier returns 409 and the web app shows "You already have a pet." (the denied path).

Real run: [registration tx](https://chainscan-galileo.0g.ai/tx/0x24340bccc045b7ca596aaf05e32e8331445ca82b77721f755a3a47e1e52148f3).

## What worked

- The relying-party setup in the Developer Portal (app ID, RP ID, generated signer key) was quick.
- `signRequest` being a pure JS import with no WASM made the server side simple.
- The QR plus polling flow worked from a phone on the first real try once the proof format matched.

## What was hard

- **Legacy vs v4 results.** With `allow_legacy_proofs: true` and a `*Legacy` preset, we got the legacy proof shape back, and the v4 verify endpoint rejected it (`responses array is required`). Switching to `allow_legacy_proofs: false` fixed it. A short note in the README about which combination returns which shape would have saved us time.
- **Where the nullifier lives.** v4 results put it in `responses[].nullifier`, legacy in `nullifier_hash`. We read the field each version binds and never a loose top-level one, so a client can't add its own nullifier to a valid proof.
- **Staging vs production.** It wasn't obvious at first that staging actions only verify with the simulator and production only with the real app. We added an `environment` switch in the web app.

## Suggestions

- An example in the idkit-core README showing the full v4 result object.
- A clear error from the verify endpoint saying "this is a legacy proof, send v4" instead of a generic validation error.
