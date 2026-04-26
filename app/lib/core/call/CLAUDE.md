# VoIP 음성 통화 — Claude 가이드

본 문서는 SnowChat의 VoIP 음성 통화 구현(Phase 8.2)에 대한 **AI 코딩 보조 규칙**을 정의한다.

## 0. 종속 관계

본 문서는 **프로젝트 루트 `CLAUDE.md`에 종속**된다. 다음 우선순위로 적용:

1. 프로젝트 루트 `CLAUDE.md` (전체 정책)
2. **본 문서** (`app/lib/core/call/CLAUDE.md` — VoIP 특화 규칙)
3. `Documentation/CONVENTION.md` (코드 스타일)
4. `Documentation/Dev-plan2/Phase8.2-VoIP-Voice-Call.md` (구현 사양)

루트 `CLAUDE.md`의 모든 규칙(파일 헤더, Zero-Knowledge, 하드코딩 금지, TODO 관리 등)이 그대로 적용되며, 본 문서는 VoIP 영역에 **추가로 강화된 규칙**을 정의한다.

---

## 1. VoIP 아키텍처 개요

```
┌─────────────────────────────────────────────────────────┐
│  Caller (A)                  Callee (B)                  │
│  ┌────────────┐              ┌────────────┐              │
│  │ flutter_   │  ←──P2P──→  │ flutter_   │              │
│  │ webrtc     │  Audio (SRTP) │ webrtc     │              │
│  └────┬───────┘              └────┬───────┘              │
│       │ Signaling (E2EE 봉투)     │ Signaling             │
│       └──────────┬───────────┬────┘                       │
│                  │           │                            │
│            ┌─────┴───────────┴─────┐                      │
│            │   SnowChat Server     │                      │
│            │   (Socket.IO relay)   │                      │
│            │   Zero-Knowledge:     │                      │
│            │   봉투 내용 미인지    │                      │
│            └───────────────────────┘                      │
│                                                           │
│  STUN: Metered.ca / Google                               │
│  TURN: Metered.ca → coturn (V2)                          │
└─────────────────────────────────────────────────────────┘
```

### 1.1 핵심 구성 요소

| 컴포넌트 | 위치 | 역할 |
|----------|------|------|
| `CallService` | `core/call/call_service.dart` | WebRTC PeerConnection 관리 |
| `CallSignaling` | `core/call/call_signaling.dart` | 시그널링 페이로드 **Sealed Sender 봉투** (24.2, 5차 보강) |
| `CallKitManager` | `core/call/callkit_manager.dart` | iOS CallKit + Android ConnectionService |
| `TurnCredentialManager` | `core/call/turn_credential_manager.dart` | TURN REST API 자격증명 캐싱 |
| `CallNotifier` | `features/call/providers/call_provider.dart` | 통화 상태 머신 (Riverpod) |
| `*CallScreen` | `features/call/screens/` | 발신/수신/통화중 UI |

---

## 2. 절대 금지 사항 (정책 23절: Zero-Trace)

다음 코드는 **PR 단계에서 차단**된다. 작성 시도 자체를 금지한다.

### 2.1 통화 기록 저장 금지

```dart
// ❌ 절대 금지 — drift 테이블 생성 금지
class CallLogs extends Table { ... }

// ❌ 절대 금지 — secure_storage에 통화 정보 저장 금지
await _secureStorage.write('call_history', ...);

// ❌ 절대 금지 — SharedPreferences에 통화 정보 저장 금지
await prefs.setString('last_call_id', ...);

// ❌ 절대 금지 — 메모리 캐시 필드 금지
class CallNotifier {
  CallState? _lastCall; // ❌ 종료된 통화를 보관하면 안 됨
  List<CallLog> _history = []; // ❌
}
```

### 2.2 부재중 통화 — 제한적 알림 정책 (V1.0.1, 2026-04-20)

**원칙**: 부재중 통화 정보를 **영속** 저장하지 않는다. 단 콜백을 위한 최소한의 hint 는 다음 두 가지 형태로만 허용 — 둘 다 5분 시한 (auto-expire).

#### 허용 패턴

1. **시스템 알림** (5분 후 auto-dismiss):

```dart
await flutterLocalNotificationsPlugin.show(
  DateTime.now().millisecondsSinceEpoch ~/ 1000,
  callerName,
  'Missed call',
  NotificationDetails(
    android: AndroidNotificationDetails(
      'missed_call_channel', 'Missed Calls',
      timeoutAfter: 5 * 60 * 1000, autoCancel: true,
    ),
  ),
);
```

2. **수신자 측 1:1 채팅방 system 메시지** (V1.0.1 추가):

   - 위치: 발신자와의 1:1 `LocalMessages` (`type='system'`, `eventType='missed_voice_call'`)
   - 본문: `"Missed voice call from {callerName} · HH:MM"`
   - **카운트다운 표시**: `"Auto-deletes in mm:ss"` 작은 라벨 (5분에서 매 초 감소)
   - TTL: **300초 강제** (대화방 disappearing 설정 무시)
   - 발신자 측: 무처리 (OutgoingCallScreen 의 "No answer" 표시로 충분)
   - **조건**: `prevStatus == incoming && endedReason != 'declined'` (incoming 상태에서 본인 명시 거절 외 모든 종료 = missed)
     - `timeout` (ConnectionService 60s ringer 자동 종료)
     - `ended` (발신자가 60s 안에 끊음 — 가장 흔한 패턴)
     - `busy` / `failed` / `offline` 등 시스템 사유
     - `declined` (본인이 거절 누름) → 메시지 X (인지)
   - 60s 레이트 제한: 동일 peer 60s 내 중복 차단 (in-memory `Map<String, DateTime>`, 영속 X)
   - 기존 `system_message_bubble` 인프라 재사용 — `_MissedCallBubble` private StatefulWidget (Timer 1s, mounted 시 dispose cancel)
   - 5분 후 expire timer (`expiring_message_manager`) 가 drift row 자동 삭제 → 영속 X

#### 여전히 금지

```dart
class MissedCalls extends Table {}  // ❌ 새 테이블
class CallLogs extends Table {}     // ❌ 통화 기록
final missedCount = ...;            // ❌ 카운터
state.missedCalls.add(...);         // ❌ 메모리 list
```

#### 정책 정신

5분 한도 = "콜백 hint" 의 최소 시간. 영구 저장 X → Zero-Trace 유지.

### 2.3 통화 녹음 관련 코드 금지

```dart
// ❌ 절대 금지 — 녹음 API
import 'package:record/record.dart';        // ❌ 패키지 import 금지
final recorder = AudioRecorder();           // ❌
MediaRecorder recorder;                     // ❌

// ❌ 절대 금지 — 녹음 권한 요청
await Permission.audio.request();           // ❌ (음성 녹음 컨텍스트)

// ❌ 절대 금지 — 통화 중 오디오 stream 캡처
_localStream.getAudioTracks().first.captureFrame(...); // ❌
```

### 2.4 시스템 통화 앱 통합 금지 (iOS Phone / Android Telecom DB)

```swift
// iOS — ❌ 절대 금지
let config = CXProviderConfiguration()
config.includesCallsInRecents = true  // ❌ 반드시 false

// ✓ 필수
config.includesCallsInRecents = false  // 정책 강제
```

```kotlin
// Android — ❌ 절대 금지 (ManagedConnectionService)
// PhoneAccount.CAPABILITY_CALL_PROVIDER 사용 시 시스템 통화 기록에 추가됨

// ✓ 필수 — Self-Managed 모드
PhoneAccount.builder(handle, "SnowChat")
  .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
  .build()
```

### 2.5 서버 메타데이터 저장 금지

```typescript
// ❌ 절대 금지 — server/src/handlers/callHandler.ts
socket.on('call_invite', async (payload) => {
  // ❌ DB 저장 금지
  await prisma.callLog.create({ ... });
  
  // ❌ 통화 메타데이터 로그 금지
  logger.info('Call from X to Y', { caller, callee });
  
  // ❌ 메트릭 카운터에 사용자 ID 포함 금지
  metrics.increment('calls.total', { caller, callee });
  
  // ❌ Redis에 통화 정보 저장 금지
  await redis.set(`call:${callId}`, JSON.stringify(payload));
});

// ✓ 허용 — 메모리 only relay
socket.on('call_invite', async (payload) => {
  await relay(io, payload.recipientSnowchatId, 'call_invite', payload);
  // 함수 종료 → payload 변수 GC 대상
});
```

### 2.6 푸시 페이로드 메타데이터 노출 금지

```typescript
// ❌ 절대 금지 — APNs/FCM payload에 평문 메타데이터
await apnsProvider.send({
  payload: {
    callerSnowchatId: 'snow...',  // ❌ 평문 노출
    callerDisplayName: 'Alice',   // ❌ 평문 노출
    callId: '...',                // ❌ 평문 노출
  },
}, voipPushToken);

// ✓ 필수 — nonce only
await apnsProvider.send({
  payload: {
    type: 'incoming_call',
    nonce: generateNonce(),       // 평문 메타데이터 0
  },
}, voipPushToken);
// 클라이언트는 nonce로 SnowChat 서버에 1:1 E2EE 메시지 fetch
```

### 2.6.1 FCM Voice Push (Android) — Phase I, 2026-04-21

Phase 8.2 §25의 FCM Voice Push 경로도 §2.6 규칙을 그대로 따른다. 추가 강화 조항:

```typescript
// ❌ 절대 금지 — FCM payload에 notification 필드 사용
await messaging.send({
  token,
  data: { type: 'incoming_call', nonce },
  notification: { title: '...', body: '...' },  // ❌ data-only 위반
  // Android가 system tray만 띄우고 Dart onBackgroundMessage 미실행.
  // 설사 notification UX를 원해도 VoIP 경로에선 금지 — CallKit이 UI 제공.
});

// ❌ 절대 금지 — VoIP payload에 callerName/callerSnowchatId 포함
data: {
  type: 'incoming_call',
  nonce,
  callerName: 'Alice',           // ❌ 평문 노출
  callerSnowchatId: 'snow...',   // ❌ 평문 노출
}

// ✓ 필수 — nonce + expiresAt 만
data: {
  type: 'incoming_call',
  nonce,                           // 32-byte base64url, Redis key
  expiresAt: String(Date.now() + 60_000),
}
```

**Android CallKit 표시 정책** (§25.3 사용자 확정, Signal 패턴):

```dart
// ❌ 절대 금지 — FCM 경로 CallKit 표시에 실제 발신자 이름
await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
  nameCaller: callerName,        // ❌ 평문 노출 경로 — 백그라운드 isolate 단계
  handle: callerSnowchatId,      // ❌
));

// ✓ 필수 — 익명 표시 (수락 후 메인 isolate에서 실제 이름으로 update)
await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
  id: nonce,
  nameCaller: 'SnowChat Call',   // 익명 (Signal 패턴)
  handle: '',                    // ID/전화번호 노출 0
));
```

**Redis pending envelope 가드** (서버 측):

```typescript
// ✓ 필수 — TTL 60s + fetch 후 즉시 DEL
await redis.setex(`voip:pending:${nonce}`, 60, envelope);
// ...fetch 시
const env = await redis.get(key);
await redis.del(key);  // 1회성 보장 — persist 0
```

**iOS 분기 차단**: Phase I 시점 iOS는 Apple Dev cert 미확보 → `osType === 'android'` 필터로 발송 0. 상세 `Documentation/TO-DO/ios-voip-push.md`.

---

## 3. 시그널링 페이로드 E2EE — Sealed Sender 기반 (24.2절, 5차 보강) — 필수

### 3.1 원칙

**모든 시그널링 메시지는 Sealed Sender 봉투로 감싸서 전송**한다. 내부는 Phase 5 Double Ratchet으로 암호화되고, 외부는 Phase 10.1 Sealed Sender로 한 번 더 래핑된다. 서버는 봉투(envelope)를 불투명한 base64 문자열로 취급하며, **SDP/ICE 후보 내용은 물론 발신자 ID조차 보지 못한다**.

메시징의 `sendSealedMessage()` 패턴과 동일 구조. Signal 메신저가 VoIP 시그널링을 일반 메시지 채널로 전송하여 Sealed Sender 혜택을 자동 수용하는 것과 동일 철학.

### 3.2 발신 패턴

```dart
// ❌ 나쁜 예 1 — 평문 전송 (서버가 SDP를 봄)
_socketManager.emit('rtc_offer', {
  'recipientSnowchatId': recipientId,
  'sdp': offer.sdp,  // ❌ 평문!
});

// ❌ 나쁜 예 2 — E2EE 봉투만 (서버가 발신자 ID를 봄) — 5차 보강 이전 구설계
await _callSignaling.sendEncryptedSignaling(...);  // ❌ 폐기됨

// ✓ 좋은 예 — Sealed Sender 봉투
await _callSignaling.sendSealedSignaling(
  recipientId: recipientId,
  eventType: 'rtc_offer',
  innerPayload: {
    'callId': callId,
    'sdp': offer.sdp,
    'fingerprint': _parseFingerprint(offer.sdp),
    'fingerprintSignature': base64Encode(
      _signal.signWithIdentityKey(fingerprintBytes),
    ),
  },
);
```

### 3.3 모든 통화 이벤트에 적용

다음 이벤트는 **반드시** Sealed Sender 봉투를 거쳐야 한다:

- `call_invite` — 통화 초대
- `call_answer` — 수락
- `call_end` — 종료
- `rtc_offer` — SDP offer
- `rtc_answer` — SDP answer
- `ice_candidate` — ICE 후보
- `call_busy` — 통화 중
- `call_ringing` — 벨소리 시작

서버 측 단일 이벤트 `sealed_call_signaling`만 존재하며, 이벤트 타입은 봉투 내부. 평문으로 전달되는 것은 **수신자 ID (`recipientSnowchatId`)** 뿐 (라우팅 필수).

### 3.4 봉투 형식

```dart
// 최내부 (Sealed Sender + Double Ratchet 둘 다 통과)
{
  'type': 'rtc_offer',
  'data': { /* SDP, fingerprint, signature 등 */ },
  'timestamp': '2026-04-17T12:34:56Z',
}

// 중간층 — Double Ratchet 암호문 (Sealed Sender 봉투 안)
{
  'drCiphertext': <bytes>,
  'drMessageType': 1,  // 1=normal, 2=prekey
}

// 최외부 — 서버가 보는 부분
{
  'recipientSnowchatId': 'snow...',      // ✓ 평문 (라우팅 필수)
  'envelope': 'base64-sealed-ciphertext', // ✓ Sealed Sender 봉투
  // ❌ senderSnowchatId 없음 — Sealed Sender가 내부에 은폐
  // ❌ messageType 없음 — Sealed Sender 내부에 포함
}
```

### 3.5 서버 `sealed_call_signaling` 핸들러 — 완전 불투명

```typescript
// server/src/handlers/callHandler.ts
socket.on('sealed_call_signaling', async (payload: {
  recipientSnowchatId: string;
  envelope: string;
}) => {
  // ❌ 금지: envelope 디코딩 / 이벤트 타입 추론 / 발신자 ID 첨부 / 로그 기록
  // ✓ 허용: 수신자 ID 라우팅 + envelope 원본 그대로 forward
  await relay(io, payload.recipientSnowchatId, 'sealed_call_signaling', {
    envelope: payload.envelope,  // senderSnowchatId 첨부 절대 금지
  });
});
```

메시징 `sealed_message` 이벤트와 동일한 불투명 relay 패턴. 서버는 "누가 누구에게 통화 시그널링을 보냈는지"를 **모른다** — 수신자 ID만 알 뿐.

---

## 4. Safety Number / SAS (24.3절) — 필수

### 4.1 자동 검증 (모든 통화)

```dart
// 발신 측 — fingerprint를 Ed25519로 서명
final fingerprint = _parseFingerprint(localSdp);
final signature = _signal.signWithIdentityKey(
  Uint8List.fromList(utf8.encode(fingerprint)),
);

// 수신 측 — 서명 검증 + SDP fingerprint 일치 검증
final sdpFingerprint = _parseFingerprint(received['sdp']);
if (sdpFingerprint != received['fingerprint']) {
  throw CallVerificationException('Fingerprint mismatch — SDP forged');
}
if (!_signal.verifySignature(
  fingerprintBytes,
  remoteSignature,
  remoteIdentityKey,
)) {
  throw CallVerificationException('Signature invalid');
}
// 검증 실패 시 통화 즉시 차단
```

### 4.2 SAS 표시 (사용자 검증)

`ActiveCallScreen`에 4자리 SAS를 항상 표시:

```dart
final sas = _computeSAS(localFingerprint, remoteFingerprint);
// HKDF-SHA256으로 도출한 4자리 숫자

// UI 표시 (필수)
Text('안전 번호: $sas', style: ...)
Text('음성으로 확인하세요', style: ...)
```

---

## 5. 메모리 wipe — 필수

### 5.1 통화 종료 시 명시적 wipe

```dart
Future<void> _cleanup() async {
  await _peerConnection?.close();
  _localStream?.getTracks().forEach((t) => t.stop());

  // 모든 필드 명시적 wipe
  _peerConnection = null;
  _localStream = null;
  _callId = null;
  _remoteSnowchatId = null;
  _remoteDisplayName = null;
  _alwaysRelay = false;
  _muted = false;
  _speakerOn = false;
  _startedAt = null;
  _localFingerprint = null;
  _remoteFingerprint = null;
  _sas = null;

  // CallProvider state 초기화
  state = const CallState.idle();

  // Debug 빌드: wipe 검증
  assert(_peerConnection == null);
  assert(_callId == null);
  assert(_remoteSnowchatId == null);
}
```

### 5.2 종료 후 메타데이터 보관 금지

```dart
// ❌ 절대 금지
class CallNotifier {
  CallState? lastCall;       // ❌
  String? lastRemoteId;      // ❌
  Duration? lastDuration;    // ❌
  DateTime? lastEndedAt;     // ❌
}
```

---

## 6. 화면 캡처 / 백그라운드 스냅샷 방지 — 필수

### 6.1 Android — `FLAG_SECURE`

```dart
// ActiveCallScreen.initState()
if (Platform.isAndroid) {
  await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
}

// dispose()
if (Platform.isAndroid) {
  await FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
}
```

### 6.2 iOS — 백그라운드 스냅샷 가림

```dart
// AppLifecycleState.inactive 감지 시 통화 화면을 빈 view로 덮기
// (iOS는 백그라운드 진입 시 자동 스냅샷 생성)
```

---

## 7. iOS CallKit / Android ConnectionService 필수 설정

### 7.1 iOS CallKit

| 설정 | 값 | 사유 |
|------|:--:|------|
| `includesCallsInRecents` | **`false`** | 시스템 Phone 앱 노출 차단 |
| `supportsVideo` | `false` | MVP는 음성만 |
| `maximumCallGroups` | `1` | 동시 통화 차단 |
| `maximumCallsPerCallGroup` | `1` | 동일 |

### 7.2 Android ConnectionService

| 설정 | 값 | 사유 |
|------|:--:|------|
| `PROPERTY_SELF_MANAGED` | ✓ | Telecom DB 분리 |
| `CAPABILITY_VIDEO_CALLING` | ✗ | MVP는 음성만 |

### 7.3 flutter_callkit_incoming 사용 시

패키지가 `includesCallsInRecents = false`를 노출하지 않으면:
1. 패키지 PR 제출
2. 또는 native 코드 직접 통합

**기본값 그대로 사용 금지**.

---

## 8. Always Relay 옵션 (13절)

### 8.1 사용자 설정

```dart
// 설정 → 개인정보 → 통화
// "항상 Relay 사용 (IP 주소 숨기기)"
final alwaysRelay = await _secureStorage.read('call_always_relay') == 'true';
```

### 8.2 PeerConnection 설정

```dart
final config = <String, dynamic>{
  'iceServers': await _turnManager.getIceServers(),
  if (alwaysRelay) 'iceTransportPolicy': 'relay',
  'bundlePolicy': 'max-bundle',
  'rtcpMuxPolicy': 'require',
};
```

### 8.3 양쪽 OR 연산

```dart
// call_invite payload에 alwaysRelay 포함
// 수신자는 자신의 선호도와 OR 연산 후 최종 결정
final useRelay = myPreference || remotePreference;
```

---

## 9. 코드 작성 시 필수 패턴

### 9.1 헤더 주석 (CLAUDE.md 규칙)

```dart
/// @file        call_service.dart
/// @description WebRTC PeerConnection 관리 + 시그널링 E2EE 봉투 통합
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     YYYY-MM-DD
/// @lastUpdated YYYY-MM-DD
///
/// @functions
///  - CallService.startCall(): 통화 발신
///  - CallService.answerCall(): 통화 수락
///  - CallService._cleanup(): 메모리 wipe (정책 23절)
```

### 9.2 통화 상태 머신

```dart
enum CallStatus {
  idle,        // 대기
  outgoing,    // 발신 중
  incoming,    // 수신 알림
  connecting,  // ICE 협상
  active,      // 통화 중
  ended,       // 종료 (cleanup 진행)
}

// 상태 전이는 CallNotifier에서만 수행
// 외부에서 직접 state = ... 금지
```

### 9.3 동시 통화 (Busy) 처리

```dart
Future<void> handleIncomingCall(CallInvitePayload payload) async {
  if (state.status != CallStatus.idle) {
    // Busy 응답 (E2EE 봉투로)
    await _callSignaling.sendEncryptedSignaling(
      recipientId: payload.callerSnowchatId,
      eventType: 'call_end',
      innerPayload: {
        'callId': payload.callId,
        'reason': 'busy',
      },
    );
    return;
  }
  // ... 정상 수신 처리
}
```

### 9.4 권한 거부 fallback

```dart
Future<bool> _ensureMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (status.isGranted) return true;

  // UI에서 설정 이동 다이얼로그 표시
  return false;
}
```

### 9.5 ICE Restart (네트워크 전환)

```dart
_peerConnection!.onIceConnectionState = (state) {
  if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
    _restartIce();
  }
};

Future<void> _restartIce() async {
  final offer = await _peerConnection!.createOffer({'iceRestart': true});
  await _peerConnection!.setLocalDescription(offer);
  // E2EE 봉투로 전송
  await _callSignaling.sendEncryptedSignaling(
    recipientId: _remoteSnowchatId!,
    eventType: 'rtc_offer',
    innerPayload: {
      'callId': _callId,
      'sdp': offer.sdp,
      'restart': true,
    },
  );
}
```

---

## 10. CI lint 차단 패턴 (정책 검증)

다음 grep 패턴은 PR 단계에서 차단된다. 코드에 절대 등장하면 안 된다.

```bash
# 통화 기록 저장 패턴
grep -rn "class CallLog" app/lib/                            # ❌
grep -rn "callLogs" app/lib/core/database/                   # ❌
grep -rn "prisma\.callLog" server/src/                       # ❌
grep -rn "lastCall\s*=" app/lib/features/call/               # ❌
grep -rn "callHistory" app/lib/                              # ❌
grep -rn "missedCallCount" app/lib/                          # ❌

# 녹음 패턴
grep -rn "MediaRecorder" app/lib/                            # ❌
grep -rn "AudioRecorder" app/lib/features/call/              # ❌
grep -rn "package:record/" app/lib/features/call/            # ❌
grep -rn "captureFrame" app/lib/features/call/               # ❌

# 평문 시그널링 패턴
grep -rn "emit.*'rtc_offer'.*sdp" app/lib/                   # ❌ (Sealed 봉투 우회)
grep -rn "emit.*'call_invite'.*callerSnowchatId" app/lib/    # ❌
grep -rn "emit.*'call_signaling'" app/lib/                   # ❌ (구설계, sealed_call_signaling만 허용)
grep -rn "senderSnowchatId" server/src/handlers/callHandler  # ❌ (Sealed Sender 우회 — 발신자 ID 평문 첨부 금지)

# CallKit 위반 패턴
grep -rn "includesCallsInRecents.*true" app/ios/             # ❌
grep -rn "CAPABILITY_CALL_PROVIDER" app/android/             # ❌ (self-managed 아님)

# 평문 푸시 페이로드
grep -rn "callerDisplayName" server/src/services/PushNotification # ❌

# FCM Voice Push (Phase I) 위반 패턴
grep -rn "sendVoipIncomingCall.*callerName" server/src/             # ❌ (payload에 이름 평문)
grep -rn "sendVoipIncomingCall.*callerSnowchatId" server/src/       # ❌
grep -rn "sendVoipIncomingCall.*callId" server/src/services/        # ❌ (callId도 메타데이터)
grep -rn "voip:pending.*SETEX.*[^6][0-9]\{3,\}" server/src/         # ❌ (TTL 60s 초과 금지)
grep -rn "type.*incoming_call.*notification" server/src/            # ❌ (data-only 강제)
grep -rn "showCallkitIncoming.*nameCaller.*[^S]" app/lib/core/call/voip_push # ❌ (익명 강제: "SnowChat Call" 외 금지)

# 메타데이터 로그
grep -rn "logger\.(info|debug).*call.*caller" server/src/    # ❌
grep -rn "debugPrint.*call.*recipient" app/lib/features/call # ❌
```

---

## 11. 보안 검증 체크리스트 (PR 시 필수)

VoIP 관련 PR을 작성하거나 리뷰할 때 다음을 모두 확인한다:

### 11.1 정책 준수

- [ ] 통화 기록 DB 모델/테이블 생성 없음 (Prisma `CallLog` 또는 drift `call_logs`)
- [ ] 부재중 통화 영속화 코드 없음
- [ ] 통화 녹음 API/패키지 사용 없음
- [ ] CallKit `includesCallsInRecents = false` 명시
- [ ] Android `PROPERTY_SELF_MANAGED` 사용
- [ ] 서버 callHandler에 DB/로그/메트릭 없음
- [ ] 푸시 페이로드 nonce-only

### 11.2 암호 보안

- [ ] 모든 시그널링이 E2EE 봉투를 거침
- [ ] DTLS fingerprint Ed25519 서명 검증
- [ ] SAS 4자리 UI 표시
- [ ] DH 결과 all-zero 차단 (Phase 5 인프라)
- [ ] 키 정보 debugPrint 없음

### 11.3 메모리 / forensic

- [ ] `_cleanup()`에서 모든 필드 명시적 wipe
- [ ] Debug `assert`로 wipe 검증
- [ ] 종료된 통화의 메타데이터 보관 필드 없음
- [ ] Android `FLAG_SECURE` 적용
- [ ] iOS 백그라운드 스냅샷 가림

### 11.4 사용성

- [ ] 권한 거부 시 fallback 다이얼로그
- [ ] 동시 통화 (busy) 응답
- [ ] ICE restart 구현 (네트워크 전환)
- [ ] 첫 통화 시 정책 명시 다이얼로그
- [ ] ActiveCallScreen에 🔒 E2EE 표시

---

## 12. 작업 시 우선순위

### 12.1 Phase별 의존성

```
Phase A (패키지)
  ↓
Phase B (서버 시그널링 + TURN API + 봉투 처리) ─┬─→ Phase F (TURN 인프라)
  ↓                                            │
Phase C (WebRTC + 시그널링 E2EE 통합)──────────┘
  ↓
  ├─→ Phase G (Safety Number 검증)
  ↓
Phase D (UI + SAS 표시 + 정책 다이얼로그)
  ↓
Phase E (PushKit/CallKit/ConnectionService)
```

**Phase B → C → G → D → E**가 핵심 경로. Phase F(TURN)는 병렬 가능.

### 12.2 작업 시작 전 확인

1. `Documentation/Dev-plan2/Phase8.2-VoIP-Voice-Call.md` 전체 정독
2. 본 문서의 정책(2~11절) 숙지
3. 사전 준비 체크리스트(20절) — Apple Developer, TURN_SECRET 등
4. 외부 의존성(flutter_webrtc 등) 빌드 사전 검증

---

## 13. 예외 처리 / 정책 변경 요청

본 문서의 규칙을 위반해야 할 정당한 사유가 있다면:

1. **PR에서 명시적으로 사유 제시** (단순 "쉽게 가려고"는 거부)
2. **`Documentation/Dev-plan2/Phase8.2-VoIP-Voice-Call.md`에 변경 이력 추가**
3. **본 문서(`CLAUDE.md`)도 함께 업데이트**
4. **23절 Zero-Trace 정책의 일관성 매트릭스(23.10) 재검증**

특히 다음 항목은 **사용자 명시적 결정 없이 변경 불가**:
- 통화 기록 저장 도입
- 통화 녹음 기능 도입
- 부재중 통화 기록 도입
- `includesCallsInRecents = true` 변경
- 시그널링 평문 전송
- Safety Number 검증 생략

---

## 14. 참조

- **상위 정책**: 프로젝트 루트 `CLAUDE.md`
- **구현 사양**: `Documentation/Dev-plan2/Phase8.2-VoIP-Voice-Call.md`
- **보안 백서**: `Documentation/Whitepaper/SnowChat-Signal-WhatsApp-보안비교.md`
- **E2EE 백서**: `Documentation/Whitepaper/SnowChat-E2EE-Whitepaper.md`
- **코딩 컨벤션**: `Documentation/CONVENTION.md`
- **WebRTC 표준**: RFC 8825, RFC 5764 (DTLS-SRTP), RFC 5766 (TURN), RFC 7635 (TURN REST API)

---

## 15. 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-04-07 | 초판 작성 — Phase 8.2 24절 보강까지 모든 정책 반영 |
| 2026-04-17 | 5차 보강 — 시그널링 페이로드를 **Sealed Sender 봉투**로 전환 (3절 전면 재작성). `call_signaling` → `sealed_call_signaling` 이벤트 단일화. 발신자 메타데이터까지 서버로부터 은폐. 그룹 통화는 V3 최후 유보(마지막 구현 예정)로 재분류 — 관련 금지 패턴은 변동 없음. |
| 2026-04-20 | V1.0.1 — §2.2 부재중 통화 정책을 "제한적 알림 정책" 으로 전환. 수신자 측 1:1 채팅방에 5분 강제 TTL `system` 메시지 insert 허용 (기존 인프라 재사용, 새 테이블 X, 영속 X, 60s peer 레이트 제한). 콜백 hint 가 시스템 알림 dismiss 후에도 채팅방에서 5분 잔존 → UX 개선 + Zero-Trace 정신 유지. |
| 2026-04-20 | V1.0.1 후속 — 트리거 조건 확장: `endedReason == 'timeout'` → `prevStatus == incoming && endedReason != 'declined'`. iPhone 발신자가 60s 안에 끊는 흔한 패턴 (reason='ended') 도 cover. UI: `_MissedCallBubble` 카운트다운 (Auto-deletes in mm:ss) 추가. |
| 2026-04-21 | Phase I — FCM Voice Push (Android) 정책 확장. §2.6.1 신설: FCM 경로도 §2.6 nonce-only 원칙 + 추가 강화 (notification 필드 금지, callerName/callerSnowchatId 평문 금지, CallKit 표시는 "SnowChat Call" 익명 강제 — Signal 패턴, Redis TTL 60s + fetch 후 즉시 DEL, iOS 분기 차단). §10 CI lint grep 패턴 6개 추가. 상세 Phase 8.2 §25. |
