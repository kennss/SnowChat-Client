<div align="center">

<img src="Snowchat.ico" width="128" height="128" alt="SnowChat" />

# SnowChat

**An end-to-end encrypted messenger that needs no phone number and can run on your own server.**

E2EE messaging · Encrypted groups · Voice calls · On-device AI — one mobile app.

[![Download APK](https://img.shields.io/badge/Download-Android%20APK%20v1.0.0%2B1006-00D2FF?style=for-the-badge&logo=android)](https://github.com/kennss/SnowChat-Client/releases/download/v1.0.0%2B1006/snowchat-arm64-v8a.apk)

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B.svg?logo=flutter)](https://flutter.dev)

</div>

---

## What is SnowChat

SnowChat is an end-to-end encrypted messenger for one-to-one chats, groups and voice calls. Sign-up asks for no phone number and no email, and the server never holds the keys to any conversation. An organization can run the server itself, so the little metadata a server must see stays inside it.

---

## 📥 Download

### Android

**[⬇️ snowchat-arm64-v8a.apk (v1.0.0+1006)](https://github.com/kennss/SnowChat-Client/releases/download/v1.0.0%2B1006/snowchat-arm64-v8a.apk)**

Side-load on Android 8.0 or later. Enable "Install from unknown sources" before opening the APK. Or grab the latest from the [Releases](https://github.com/kennss/SnowChat-Client/releases) page.

### iOS

TestFlight build available on request — email **kenntkim66@gmail.com** with your Apple ID and we'll send the invitation.

---

## 🧪 Try It (5-minute walkthrough)

### 1. First launch — no phone number, no email
Open the app → **Create New Identity**. The app generates a recovery phrase and a SnowChat ID (`"snow"` + 32 hex characters). **Back up the recovery phrase — it is the only way to restore the account.** No email, no phone. You're now on the Chats tab.

### 2. Test the E2EE messenger (needs two peers)
- **With a second device:** install the app on it with a separate SnowChat ID. On either device, Chats tab → ✏️ pencil icon → enter the other peer's SnowChat ID → start chatting.
- **Solo testing:** email **kenntkim66@gmail.com** and the author will act as the second peer for a live demo (E2EE 1:1, group chat, disappearing messages, reply quotes, voice / file attachments, VoIP voice call).

To verify the **disappearing messages** flow: tap the timer icon in the message input → pick `1m` → send a message → watch it tick down and self-destruct on both peers.

To verify **reply quotes**: long-press any message → Reply → send. The new message renders with the quote box, persisted across restart.

### 3. Test the on-device AI (optional, ≥ 8 GB RAM device only)
- Open the **SnowChat AI** tab. On a device with less than 8 GB RAM (e.g. iPhone 13) the app blocks the model download and shows an "AI unavailable on this device" dialog — that gate is the test. On a 8 GB+ device the model downloads on first tap and runs **fully on-device** (no server round-trip — verify with airplane mode).
- iOS Korean translation uses the **Apple Translation API**; toggle it via the 🅰 icon in any chat.

### 4. Test the VoIP voice call
- From a 1:1 conversation, tap the 📞 phone icon. Both peers can receive on locked screen (CallKit on iOS, Telecom ConnectionService on Android). Decline / accept / end-call all work cold-launch.

### What's *not* in this build
- App Store iOS distribution — TestFlight only.
- Korean UI — locked to English at the OS level for V1 (the CallKit banner stays consistent on Korean-locale devices).

---

## Features

### 🔐 E2EE Messaging — Pure Dart Signal Protocol
- Direct Dart implementation of X3DH + Double Ratchet + Sealed Sender (1:1) and Sender Key (groups, group protocol v2).
- Messaging protocols are pure Dart, no Platform Channel. One native exception: the first-party Rust crate [`native/snowchat_zkgroup`](native/snowchat_zkgroup) — libsignal's `zkgroup` anonymous credentials for groups, and the Argon2id key derivation of the app passcode.
- Disappearing messages, read receipts, typing indicators, reply quotes.
- Powered by [`kennss/dart-signal-protocol`](https://github.com/kennss/dart-signal-protocol) — a standalone Pure Dart Signal Protocol library purpose-built in-house for SnowChat, now released as a reusable library for any Flutter project.

### 🕸️ No Social Graph on the Server
- Friend lists live only on the phone (and in a backup sealed with the recovery phrase); friend requests and acceptances are end-to-end encrypted messages.
- No friend table, no readable block list (blocks stay on the phone; the server keeps only keyed tags), no favorites, no online status or last-seen time.
- Display names travel as server-signed name certificates inside messages; one-to-one queue rows name no sender and are deleted once the recipient's device has them.

### 👥 Encrypted Groups — group protocol v2
- Membership changes only through a log signed by members and verified on every device; the server cannot add anyone to a group.
- The server stores members as zkgroup ciphertexts, and group sends name neither the sender nor the group.
- One-tap invite links — iOS Universal Links + Android App Links.

### 🔒 On-Device Protection
- Chat history in a SQLCipher-encrypted database, its key in the iOS Keychain / Android Keystore.
- App passcode (6 digits, custom numeric or alphanumeric) checked with Argon2id; auto-lock and optional biometric unlock.

### 📞 Voice Calls (VoIP)
- WebRTC P2P, Sealed Sender signaling over Socket.IO; each call's DTLS fingerprint is signed and checked against the peer's account-bound identity key.
- iOS CallKit + Android ConnectionService. No call history anywhere — the app, the server, or the iPhone's Phone app Recents.
- Cloudflare Realtime TURN, FCM Voice Push.

### 🤖 On-Device AI
- Forked `flutter_gemma` running Gemma 4 E2B (llama.cpp on iOS, LiteRT-LM on Android).
- Apple Translation API for Korean, ML Kit language detector.
- Agentic Tool Use router (calendar, contacts, photos, etc., with Just-in-Time permission).
- **Zero server transmission** — all inference happens on-device.

---

## Identity

SnowChat IDs are **not phone numbers, not emails**. They are derived from the account's public key, which comes from the recovery phrase — `"snow"` + 32 hex characters (36 total). Each device's encryption keys are signed by that account key, so knowing a contact's SnowChat ID is enough to detect a server swapping their keys. Recovery via the recovery phrase only.

---

## Tech Stack

| Layer | Stack |
|-------|-------|
| Mobile | Flutter 3.x · Dart · Riverpod · GoRouter · drift (SQLCipher-encrypted SQLite) · `flutter_secure_storage` |
| E2EE | Pure Dart Signal Protocol · pinenacl · X25519 / Ed25519 / XSalsa20-Poly1305 / HMAC-SHA256 |
| Native crypto | Rust (`native/snowchat_zkgroup`): libsignal `zkgroup` · Argon2id (RustCrypto `argon2`) · `dart:ffi` |
| VoIP | WebRTC · Socket.IO · CallKit · ConnectionService · Cloudflare TURN · FCM |
| On-device AI | flutter_gemma · Gemma 4 E2B · llama.cpp / LiteRT-LM · Apple Translation API · ML Kit |

The backend (Node.js · Express · Socket.IO · Prisma · PostgreSQL · Redis) is plaintext-blind by design — it relays ciphertext only — and its source is kept private for now. The E2EE security surface is fully open here.

---

## Build From Source

### Requirements

- Flutter 3.x (`flutter doctor` must pass)
- Dart 3.x
- Xcode 15+ (for iOS builds)
- Android Studio / Android SDK 33+ (for Android builds)
- Rust via `rustup` and `protoc` — the build hook of `packages/snowchat_zkgroup` compiles `native/snowchat_zkgroup` from source for every target

### Setup

```bash
git clone https://github.com/kennss/SnowChat-Client.git
cd SnowChat-Client
# CallKit / ConnectionService fork the app depends on by path
git clone https://github.com/kennss/flutter_callkit_incoming.git external/flutter_callkit_incoming
git -C external/flutter_callkit_incoming checkout 4b15e14
cd app

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

---

## Status

- ✅ E2EE messenger — Pure Dart Signal Protocol, internal audits (latest: 2026-11-22, build 1001)
- ✅ Encrypted groups — group protocol v2 (signed membership log, zkgroup-hidden membership, sealed group sends)
- ✅ VoIP — WebRTC + CallKit / ConnectionService
- ✅ On-device AI — Gemma 4 E2B + agentic Tool Use
- 🟡 Public beta — from build 1001
- 🟡 Independent external security audit

---

## License

**AGPL-3.0** — see [LICENSE](LICENSE).

If you fork or run a network-modified version of this app, you must publish your source under the same license. This is intentional: it keeps the E2EE security surface verifiable end-to-end.

---

## Author

**Kennt Kim** — [Calida Lab](https://snowchat.calidalab.ai)
