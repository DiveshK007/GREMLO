# Releasing the Mac app

A tag `vX.Y.Z` pushed to GitHub runs `.github/workflows/release.yml`. It:
1. Runs the Swift tests.
2. Builds the universal app, signs it with the Developer ID (hardened runtime, `apps/mac/Gremlo.entitlements`).
3. Notarizes the dmg, staples it, and checks it with `spctl`.
4. Signs the dmg for Sparkle and attaches the dmg, its sha256 and `appcast.xml` to the release.

The app's update feed is `https://github.com/DiveshK007/GREMLO/releases/latest/download/appcast.xml`, so publishing a
release publishes the update. No GitHub Pages or website deploy is involved. To move the feed somewhere else, set
`SPARKLE_FEED` for `scripts/release-mac.sh`. Installed apps keep the feed they shipped with.

If a secret or variable below is missing, the job stops with its name. It never ships an unsigned or unsignable build.

## Secrets and variables (Settings, Secrets and variables, Actions)

| Name | Kind | What |
|---|---|---|
| `APPLE_CERT_P12` | secret | The "Developer ID Application" certificate and its private key, exported from Keychain Access as .p12, then base64: `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERT_PASSWORD` | secret | The password you gave the .p12 export |
| `APPLE_TEAM_ID` | secret | The 10-character team ID (developer.apple.com, Membership) |
| `APPLE_ID` | secret | The Apple ID email of the developer account |
| `APPLE_APP_PASSWORD` | secret | An app-specific password for that Apple ID (account.apple.com, Sign-In and Security, App-Specific Passwords) |
| `SPARKLE_PRIVATE_KEY` | secret | The EdDSA private key that signs updates (below) |
| `SPARKLE_PUBLIC_KEY` | variable | Its public key. Not secret: it is baked into every app's Info.plist |

## The Sparkle key, once

Run these on your own Mac, not in CI. `sign_update` and `generate_keys` come from the same pinned Sparkle zip as
`apps/mac/Package.swift`.

```bash
cd "$(mktemp -d)"
curl -sSLO https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip
echo "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a  Sparkle-for-Swift-Package-Manager.zip" | shasum -a 256 -c
unzip -q Sparkle-for-Swift-Package-Manager.zip 'bin/*'

./bin/generate_keys            # makes the key in your login keychain and prints the PUBLIC key
gh variable set SPARKLE_PUBLIC_KEY --body "<the public key it printed>"

./bin/generate_keys -x sparkle_private.key     # exports the PRIVATE key to a file
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private.key
rm -P sparkle_private.key                       # the copy in your keychain stays as the backup
```

- The private key lives in two places only: your login keychain (item "Private key for signing Sparkle updates") and the GitHub secret.
- **If you lose it**, installed apps can't accept new updates. You would have to ship a release with a new key, and every user would install it by hand once. Back up the keychain item.
- **If it leaks**, someone with it and a way to serve the feed could push an update. Make a new key, ship a release with it, and delete the old secret.

## Cutting a release

1. Add the version's section to `CHANGELOG.md` and commit it.
2. `git tag -a vX.Y.Z -m "Gremlo X.Y.Z" && git push origin vX.Y.Z`
3. Watch the run: `gh run watch`. Notarization usually takes 2 to 10 minutes.
4. Check the release: `gh release view vX.Y.Z`. It should list `Gremlo-X.Y.Z.dmg`, `.sha256` and `appcast.xml`.
5. Update the README download link and sha256 to the new dmg.

## Checking a downloaded dmg

```bash
spctl --assess --type open --context context:primary-signature -v Gremlo-X.Y.Z.dmg   # "accepted, source=Notarized Developer ID"
xcrun stapler validate Gremlo-X.Y.Z.dmg                                              # "The validate action worked!"
codesign -dv --verbose=2 /Applications/Gremlo.app 2>&1 | grep -E "Authority|TeamIdentifier|flags"   # Developer ID, your team, runtime
```

## Builds from source

`install.sh` runs the same script with no signing identity and no Sparkle key. The app is ad hoc signed and has no
updater, so Settings, General says "Built from source". Run the install line again to update.
