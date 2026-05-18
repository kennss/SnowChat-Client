<div align="center">

<img src="Snowchat.ico" width="128" height="128" alt="SnowChat" />

# SnowChat

**The first sovereign community stack on Solana.**

E2EE messenger · Multi-wallet · On-chain NFT marketplace · Community fund — one mobile app.

[![Download APK](https://img.shields.io/badge/Download-Android%20APK%20v1.0.0%2B295-00D2FF?style=for-the-badge&logo=android)](https://github.com/kennss/SnowChat-Client/releases/download/v1.0.0%2B295/snowchat-v1.0.0%2B295-20260514.apk)

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE)
[![Solana](https://img.shields.io/badge/Solana-Devnet-9945FF.svg)](https://solana.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?logo=flutter)](https://flutter.dev)

</div>

---

## What is SnowChat

SnowChat fuses an **E2EE messenger**, **encrypted community channels** (the Discord replacement), a **multi-wallet**, an **on-chain NFT marketplace** (a Tensor-fork Anchor program), and a **community fund** where 50% of every trade flows back to the creator-led community — into one mobile app.

Web3 communities run on Discord — BAYC, MonkeyDAO, OpenSea, repeatedly hacked, millions in NFTs drained. Tensor stripped creator royalties to compete on price, and creators lost the income that funded their community. Two stories, one root cause: intermediaries capturing value Web3 was supposed to return to creators and communities.

**SnowChat reclaims both sovereignties — by mechanism, not enforcement.**

---

## 📥 Download

### Android

**[⬇️ snowchat-v1.0.0+295-20260514.apk](https://github.com/kennss/SnowChat-Client/releases/download/v1.0.0%2B295/snowchat-v1.0.0%2B295-20260514.apk)**

Side-load on Android 8.0 or later. Enable "Install from unknown sources" before opening the APK. Or grab the latest from the [Releases](https://github.com/kennss/SnowChat-Client/releases) page.

### iOS

TestFlight build available on request — email **kenntkim66@gmail.com** with your Apple ID and we'll send the invitation. App Store submission is pending Phase 0 (legal entity / KYC / mainnet audit).

---

## 🧪 Try It (5-minute walkthrough)

Designed so a judge or first-time visitor can verify every claim in this README on real hardware in five minutes.

### 1. First launch — no signup
Open the app → **Create new wallet**. The app generates a BIP-39 mnemonic and a SnowChat ID (`"snow"` + 32 hex characters). **Save the mnemonic — it is the only recovery path.** No email, no phone, no centralized account. You're now on the Chats tab.

### 2. Test the E2EE messenger (needs two peers)
- **With a second device:** install the app on it with a separate SnowChat ID. On either device, Chats tab → ✏️ pencil icon → enter the other peer's SnowChat ID → start chatting.
- **Solo testing:** email **kenntkim66@gmail.com** and the author will act as the second peer for a live demo (E2EE 1:1, group chat, disappearing messages, reply quotes, voice / file attachments, VoIP voice call).

To verify the **disappearing messages** flow: tap the timer icon in the message input → pick `1m` → send a message → watch it tick down and self-destruct on both peers.

To verify **reply quotes**: long-press any message → Reply → send. The new message renders with the WhatsApp-style green quote box, persisted across restart.

### 3. Test the on-chain marketplace (Solana Devnet)
- **Network:** the wallet defaults to Devnet in this build — no flag needed.
- **Faucet:** Wallet tab → Receive → copy the Solana address → paste into [faucet.solana.com](https://faucet.solana.com) and request 1 SOL.
- **List a cNFT:** Wallet tab → NFTs → tap any cNFT in your wallet → **List for sale** → set a price. Listing fee 0%.
- **Buy a cNFT:** another wallet (or the second test device) opens the marketplace → buy → settlement is atomic. **50% of the sale price routes to the verified-creator community fund** in the same transaction. The community-fund address is shown on the listing detail.
- **Verify on-chain:** the transaction signature shown after the buy resolves on [Solana Explorer (devnet)](https://explorer.solana.com/?cluster=devnet) and the community-fund split shows as a discrete transfer instruction.

Anchor program source: [`kennss/marketplace`](https://github.com/kennss/marketplace) on branch `feature/snowchat-community-fee-share`. Program ID is also printed under Settings → About in the app.

### 4. Test the on-device AI (optional, ≥ 8 GB RAM device only)
- Open the **SnowChat AI** tab. On a device with less than 8 GB RAM (e.g. iPhone 13) the app blocks the model download and shows an "AI unavailable on this device" dialog — that gate is the test. On a 8 GB+ device the model downloads on first tap and runs **fully on-device** (no server round-trip — verify with airplane mode).
- iOS Korean translation uses the **Apple Translation API**; toggle it via the 🅰 icon in any chat.

### 5. Test the VoIP voice call
- From a 1:1 conversation, tap the 📞 phone icon. Both peers can receive on locked screen (CallKit on iOS, Telecom ConnectionService on Android). Decline / accept / end-call all work cold-launch.

### What's *not* in this build
- Mainnet — pending Phase 0 (legal entity, KYC, third-party audit).
- App Store iOS distribution — TestFlight only.
- Korean UI — locked to English at the OS level for V1 (the CallKit banner stays consistent on Korean-locale devices).

---

## Features

### 🔐 E2EE Messaging — Pure Dart Signal Protocol
- Direct Dart implementation of X3DH + Double Ratchet (1:1) + Sender Key Hybrid (group).
- No `libsignal` binary, no Platform Channel — pure Dart, three internal audits.
- Disappearing messages, read receipts, typing indicators, WhatsApp-style reply quotes.
- Powered by [`kennss/dart-signal-protocol`](https://github.com/kennss/dart-signal-protocol) — a standalone Pure Dart Signal Protocol library purpose-built in-house for SnowChat, now released as a reusable library for any Flutter project.

### 🏘 Communities — Discord, but encrypted and on-chain
- Persistent community channels — each channel is an E2EE group, server only ever sees ciphertext.
- Sender Key Hybrid + pairwise fallback distribution — Signal's actual group protocol, not custom crypto. Out-of-order delivery, multi-generation key rotation, retry safety net all included.
- One-tap channel invite links (`snowchat://invite/<code>`) — iOS Universal Links + Android App Links, no QR friction.
- On-chain treasury baked in — every community is bound to a verified Metaplex collection that automatically receives the 50% marketplace-fee split on every trade. The treasury is on-chain and auditable; there is no multi-sig "trust us" layer.
- No bot framework, no third-party server, no token to compromise — community membership lives in your wallet, channel content lives in your device. The Discord token-phishing vector that drained BAYC / MonkeyDAO / OpenSea is structurally absent.

### 💼 Multi-Wallet (Solana, non-custodial)
- BIP-39 mnemonic + SLIP-0010 derivation.
- Phantom-compatible derivation path: `m/44'/501'/{account}'/0'`.
- Multi-account, hide / unhide, biometric gate (`local_auth`).
- iOS Keychain / Android Keystore for all key material — never on the server.

### 🛍 On-Chain NFT Marketplace
- Tensor-fork Anchor program with a custom `snowchat_vault` PDA and a 50% community-fee router.
- See [`kennss/marketplace`](https://github.com/kennss/marketplace) (branch `feature/snowchat-community-fee-share`) for the on-chain program source.
- Compressed NFTs (Bubblegum), Metaplex Token Metadata, SPL Token / ATA, Helius indexing.

### 🏛 Community Fund — 50% On-Chain Split
- Half of every trade flows directly to the creator-led community fund.
- Verified Metaplex Collection + verified creator required.
- Atomic settlement on Solana — no escrow, no opt-out, no enforcement layer.

### 📞 Voice Calls (VoIP)
- WebRTC P2P, Sealed Sender signaling over Socket.IO.
- iOS CallKit + Android ConnectionService.
- Cloudflare Realtime TURN, FCM Voice Push.

### 🤖 On-Device AI
- Forked `flutter_gemma` running Gemma 4 E2B (llama.cpp on iOS, LiteRT-LM on Android).
- Apple Translation API for Korean, ML Kit language detector.
- Agentic Tool Use router (calendar, contacts, photos, etc., with Just-in-Time permission).
- **Zero server transmission** — all inference happens on-device.

---

## Identity

SnowChat IDs are **not phone numbers, not emails**. They are deterministic hashes of the user's Solana wallet — `"snow"` + 32 hex characters (36 total). No Web2 PII, no centralized account system. Recovery via the BIP-39 mnemonic only.

---

## Tech Stack

| Layer | Stack |
|-------|-------|
| Mobile | Flutter 3.x · Dart · Riverpod · GoRouter · drift (SQLite) · `flutter_secure_storage` |
| E2EE | Pure Dart Signal Protocol · pinenacl · X25519 / Ed25519 / XSalsa20-Poly1305 / HMAC-SHA256 |
| Solana | Anchor (Rust) · Tensor-fork marketplace · Compressed NFTs (Bubblegum) · Metaplex Token Metadata · SPL Token · Helius |
| Wallet | BIP-39 · SLIP-0010 · `Ed25519HDKeyPair` · `local_auth` biometric gate |
| VoIP | WebRTC · Socket.IO · CallKit · ConnectionService · Cloudflare TURN · FCM |
| On-device AI | flutter_gemma · Gemma 4 E2B · llama.cpp / LiteRT-LM · Apple Translation API · ML Kit |

The backend (Node.js · Express · Socket.IO · Prisma · PostgreSQL · Redis) is plaintext-blind by design — it relays ciphertext only — and its source is kept private. The E2EE security surface is fully open here.

---

## Build From Source

### Requirements

- Flutter 3.x (`flutter doctor` must pass)
- Dart 3.x
- Xcode 15+ (for iOS builds)
- Android Studio / Android SDK 33+ (for Android builds)

### Setup

```bash
git clone https://github.com/kennss/SnowChat-Client.git
cd SnowChat-Client/app

flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Run

```bash
# Android emulator
flutter run -d emulator-5554

# iOS simulator
open -a Simulator
flutter run -d <simulator-id>
```

### Production build (Android)

```bash
flutter build apk --release --dart-define=SERVER_ENV=prod
# Output: app/build/app/outputs/flutter-apk/app-release.apk
```

---

## Related Projects

| Repo | Purpose | License |
|------|---------|---------|
| [`kennss/dart-signal-protocol`](https://github.com/kennss/dart-signal-protocol) | Pure Dart Signal Protocol library — zero native dependencies, reusable. | AGPL-3.0 |
| [`kennss/marketplace`](https://github.com/kennss/marketplace) (branch `feature/snowchat-community-fee-share`) | Tensor-fork Anchor program with `snowchat_vault` PDA + 50% community-fee router. | Apache-2.0 |

---

## Status

- ✅ Wallet V2 Phase 1 — 1:1 chat asset transfers (SOL / SPL / NFT, drift persistence, in-flight recovery)
- ✅ Wallet V2 Phase 2 — Tensor-fork marketplace + 50% community-fee split (devnet deployed)
- ✅ E2EE messenger — Pure Dart Signal Protocol, three internal audits
- ✅ Encrypted community channels — Sender Key Hybrid groups + Metaplex collection binding (Discord replacement)
- ✅ Multi-Wallet V1 — BIP-39 + SLIP-0010, Phantom-compatible derivation
- ✅ VoIP — WebRTC + CallKit / ConnectionService (Phase 8.2 A~D, G, H)
- ✅ On-device AI — Gemma 4 E2B + agentic Tool Use
- 🟡 Third-party security audit — Sec3 / Neodyme / OtterSec (funded by Solana Frontier hackathon)
- 🟡 Mainnet — after Phase 0 (entity / legal / KYC provider)

---

## License

**AGPL-3.0** — see [LICENSE](LICENSE).

If you fork or run a network-modified version of this app, you must publish your source under the same license. This is intentional: it keeps the E2EE security surface verifiable end-to-end.

---

## Author

**Kennt Kim** — [Calida Lab](https://snowchat.calidalab.ai)

Built solo over four weeks. Submitting to [Colosseum Frontier](https://www.colosseum.com/) (Solana hackathon, 2026).
