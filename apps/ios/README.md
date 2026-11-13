# Gremlo for iPhone and Apple Watch

Pairs with the Mac app by QR code (or a pasted `gremlo-pair:` code). The Mac seals its state with a key only it and
this phone have; the server relays sealed boxes it can't read.

- iPhone: the pet, the current run, waiting approvals with Allow once (Face ID) and Deny; risky commands say
  "Open on the Mac". Live Activity with the Dynamic Island (eyes and a timer, expanding to ask) and actionable
  approvals on the lock screen. Widgets: today, what's waiting, asleep after hours.
- Watch: the pet in a ring that fills as the run goes, "N waiting on you" with Allow/Deny for ordinary calls, a
  knock haptic for a new approval and success when a run ends, silent while the Mac is quiet. Complication: the
  face inside the ring.

Build (simulator):

    brew install xcodegen
    xcodegen generate
    xcodebuild -project GremloPhone.xcodeproj -scheme Gremlo -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

`simctl launch <device> dev.gremlo.phone -pairCode <code>` pairs without a tap. The shared crypto and types are
`apps/mac/Sources/GremloCore/PhoneLink.swift`, tested in the Mac package.
