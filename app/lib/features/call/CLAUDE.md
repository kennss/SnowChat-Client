# VoIP UI 계층 — Claude 가이드

본 문서는 VoIP 통화 UI 계층(`features/call/`)에 대한 **AI 코딩 보조 규칙**이다.

## 0. 종속 관계

본 문서는 다음 두 문서에 종속된다:

1. 프로젝트 루트 `CLAUDE.md` (전체 정책)
2. **`app/lib/core/call/CLAUDE.md`** (VoIP 핵심 정책 — 본 문서의 모든 규칙은 여기서 파생)

본 문서는 **UI/Provider 계층 특화 규칙**만 다룬다. 정책/암호/보안 관련 규칙은 모두 `core/call/CLAUDE.md`를 참조한다.

---

## 1. 디렉토리 구조

```
features/call/
├── providers/
│   └── call_provider.dart       # CallNotifier (Riverpod 상태 머신)
└── screens/
    ├── outgoing_call_screen.dart  # 발신 중
    ├── incoming_call_screen.dart  # 수신 알림
    └── active_call_screen.dart    # 통화 중 (SAS 표시)
```

`models/`와 `widgets/` 폴더는 **만들지 않는다**. 이유:
- **models**: `CallState`만 존재하며 `call_provider.dart` 내부에 정의 (별도 파일 불필요)
- **widgets**: 화면 간 공유 위젯이 없음 (각 screen 내 private 위젯으로 충분)

향후 위젯 분리 기준(80줄 초과)에 도달하면 `widgets/` 폴더 생성 가능.

---

## 2. CallNotifier 패턴

### 2.1 단일 인스턴스 (family 사용 금지)

```dart
// ✓ 좋음 — 전역 단일 인스턴스
final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  return CallNotifier(
    callService: ref.read(callServiceProvider),
    callSignaling: ref.read(callSignalingProvider),
    callKitManager: ref.read(callKitManagerProvider),
  );
});

// ❌ 나쁨 — family 사용 금지 (동시 통화 차단 정책)
final callProvider = StateNotifierProvider.family<...>(...); // ❌
```

**이유**: SnowChat은 동시 통화를 정책적으로 차단한다 (정책 23절). family 사용 시 여러 통화 인스턴스가 가능해져 정책 위반 위험.

### 2.2 상태 머신 전이 규칙

```dart
enum CallStatus { idle, outgoing, incoming, connecting, active, ended }
```

허용된 전이만 수행:

| 현재 | → | 다음 | 트리거 |
|------|:-:|------|--------|
| idle | → | outgoing | `startCall()` |
| idle | → | incoming | `handleIncomingCall()` |
| outgoing | → | connecting | `call_answer` 수신 |
| incoming | → | connecting | `acceptCall()` |
| connecting | → | active | ICE 연결 완료 |
| outgoing | → | ended | 거절/타임아웃/취소 |
| incoming | → | ended | 거절/타임아웃 |
| active | → | ended | 종료 |
| ended | → | idle | `_cleanup()` 완료 |

**금지된 전이**: `active → outgoing`, `idle → active`, `ended → active` 등.

### 2.3 종료 후 메타데이터 보관 금지

```dart
// ❌ 절대 금지 — core/call/CLAUDE.md 참조
class CallState {
  final CallStatus status;
  final String? lastRemoteId;        // ❌
  final Duration? lastDuration;      // ❌
  final DateTime? lastEndedAt;       // ❌
  final List<MissedCall> missedCalls; // ❌
}

// ✓ 좋음 — 활성 통화 정보만
class CallState {
  final CallStatus status;
  final String? callId;              // active 시에만
  final String? remoteSnowchatId;    // active 시에만
  final String? remoteDisplayName;   // active 시에만
  final Duration elapsed;            // active 시에만
  final bool isMuted;
  final bool isSpeakerOn;
  final String? sas;                 // 4자리 안전번호
  final bool alwaysRelay;
}
```

### 2.4 cleanup 시 모든 필드 wipe

```dart
Future<void> _cleanup() async {
  await _callService.cleanup();
  // 모든 활성 통화 필드를 idle 상태로 reset
  state = const CallState.idle();
  // assert로 검증 (debug 빌드)
  assert(state.callId == null);
  assert(state.remoteSnowchatId == null);
}
```

---

## 3. UI 구현 규칙

### 3.1 ActiveCallScreen 필수 요소

```
┌─────────────────────────────────┐
│  🔒 E2EE              03:42     │ ← 보안 표시 + 통화 시간 (필수)
│                                 │
│         [Avatar]                │
│        "B-User"                 │
│                                 │
│   ── 안전 번호 ──                │
│       1 2 3 4                   │ ← SAS 4자리 (필수, 정책 24.3)
│   음성으로 확인하세요             │
│                                 │
│   [🔇]    [🔊]    [📞]          │ ← 음소거 / 스피커 / 종료
└─────────────────────────────────┘
```

**필수 요소**:
- 🔒 E2EE 보안 표시 (우상단)
- 통화 시간 (실시간 갱신)
- 안전 번호 4자리 (SAS)
- 음소거 / 스피커 / 종료 버튼
- 상대방 이름 + 아바타

**금지 요소**:
- 통화 녹음 버튼 (정책 위반)
- 통화 기록 보기 버튼 (정책 위반)
- "최근 통화" 링크 (정책 위반)

### 3.2 IncomingCallScreen 필수 요소

```
┌─────────────────────────────────┐
│                                 │
│         [Avatar]                │
│        "A-User"                 │
│      음성 통화 수신중             │
│                                 │
│      🔒 E2EE 보호 중              │
│                                 │
│   [거절]              [수락]    │
└─────────────────────────────────┘
```

**iOS / Android 시스템 통화 UI(CallKit/ConnectionService)가 우선** 표시되며, 사용자가 앱을 직접 연 경우만 본 화면이 표시된다.

### 3.3 OutgoingCallScreen 필수 요소

```
┌─────────────────────────────────┐
│         [Avatar]                │
│        "B-User"                 │
│       Calling...                │
│       🔒 E2EE                    │
│                                 │
│           [📞]                  │ ← 취소 버튼
└─────────────────────────────────┘
```

**Audio UX — Ringback Tone (Phase J, §26)**:

- `outgoing` 또는 `connecting` 상태에서는 **ringback tone 루프 재생 필수** (`assets/audio/ringback.wav`)
- `active` 진입 시 즉시 중단 (WebRTC `voiceChat` 세션이 오디오 인수)
- `ended` 시 즉시 중단 (reason=busy면 busy tone으로 전환)
- 재생 주체: `CallService._startRingback()` / `_stopRingback()` — UI(screen)가 직접 AudioPlayer 소유 금지
- WebRTC `voiceChat` 세션 충돌 방지: `audio_session` 패키지로 카테고리 통일, ringback은 동일 카테고리에서 재생
- iOS CallKit outgoing 등록 시 시스템이 자체 ringback을 재생하는 경우 실기기 검증 후 조정

### 3.4 첫 통화 시 정책 다이얼로그 (1회만)

```dart
final acknowledged = await _secureStorage.read('voip_policy_acknowledged');
if (acknowledged != 'true') {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const VoipPolicyDialog(),
  );
  await _secureStorage.write('voip_policy_acknowledged', 'true');
}
```

다이얼로그 내용 (`core/call/CLAUDE.md` 23.6절 참조):
- ✓ 통화 내용 종단간 암호화
- ✓ 서버는 음성 데이터 미경유
- ✓ 통화 기록 미저장
- ✓ 부재중 통화 미기록
- ✓ 통화 녹음 미제공
- ※ 통화 후 다시 연락이 필요하면 메시지로 알려주세요

### 3.5 종료 사유별 표시

| reason | 표시 메시지 | Audio |
|--------|------------|-------|
| `ended` | "통화 종료" (시간 표시 X — 정책상 통화 시간 미보관) | 무음 |
| `declined` | "B-User 님이 통화를 거절했습니다" | 무음 |
| `busy` | "B-User 님이 다른 통화 중입니다" | **busy tone 2~3초 재생** (§26) |
| `timeout` / `no_answer` | "응답 없음" | 무음 |
| `failed` | "통화 연결 실패" | 무음 |
| `permission_denied` | "B-User 님이 마이크 권한을 허용하지 않았습니다" | 무음 |
| `offline` | "B-User 님이 오프라인입니다" | 무음 |

이 메시지는 **2~3초 후 자동 dismiss**되며, 어떤 데이터도 저장되지 않는다. `busy` 경로는 busy tone(`assets/audio/busy.wav`, 480+620 Hz, 0.5s on/off) 재생이 끝난 뒤 dismiss.

---

## 4. Provider 의존성

```dart
// app/lib/app/providers.dart에 등록
final callServiceProvider = Provider<CallService>((ref) {
  return CallService(
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    socketManager: ref.read(socketManagerProvider),
  );
});

final callSignalingProvider = Provider<CallSignaling>((ref) {
  return CallSignaling(
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    socketManager: ref.read(socketManagerProvider),
  );
});

final callKitManagerProvider = Provider<CallKitManager>((ref) {
  return CallKitManager();
});

final turnCredentialManagerProvider = Provider<TurnCredentialManager>((ref) {
  return TurnCredentialManager(
    apiClient: ref.read(apiClientProvider),
  );
});
```

---

## 5. 라우트 등록

```dart
// app/lib/app/router.dart
GoRoute(
  path: '/call',
  builder: (context, state) {
    final status = ref.watch(callProvider).status;
    switch (status) {
      case CallStatus.outgoing:
        return const OutgoingCallScreen();
      case CallStatus.incoming:
        return const IncomingCallScreen();
      case CallStatus.connecting:
      case CallStatus.active:
        return const ActiveCallScreen();
      default:
        return const SizedBox.shrink();
    }
  },
),
```

`/call` 라우트는 통화 상태에 따라 다른 화면을 표시한다. 별도 `/call/outgoing`, `/call/incoming` 라우트는 만들지 않는다.

---

## 6. 보안 검증 체크리스트 (UI 계층 PR)

VoIP UI 관련 PR 시 다음을 모두 확인:

- [ ] `CallState`에 종료된 통화 메타데이터 필드 없음
- [ ] `family` Provider 사용 안 함 (단일 인스턴스)
- [ ] ActiveCallScreen에 🔒 E2EE 표시 + SAS 4자리
- [ ] 통화 녹음 / 통화 기록 / 부재중 표시 UI 없음
- [ ] 첫 통화 시 정책 다이얼로그 표시 로직
- [ ] 권한 거부 시 fallback 다이얼로그
- [ ] 종료 사유별 메시지 (자동 dismiss)
- [ ] 헤더 주석 존재 (CLAUDE.md 규칙)
- [ ] Ringback tone: `outgoing`/`connecting` 재생, `active` 진입 시 즉시 중단 (Phase J, §26)
- [ ] Busy tone: `ended` + `reason=='busy'` 2~3초 재생 후 dismiss
- [ ] AudioPlayer 인스턴스는 `CallService`가 소유 (screen 계층 직접 소유 금지)
- [ ] `_cleanup()`에 AudioPlayer wipe + null assert

---

## 7. 참조

- **상위 정책**: `app/lib/core/call/CLAUDE.md`
- **프로젝트 정책**: 프로젝트 루트 `CLAUDE.md`
- **구현 사양**: `Documentation/Dev-plan2/Phase8.2-VoIP-Voice-Call.md`
- **코딩 컨벤션**: `Documentation/CONVENTION.md`

---

## 8. 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-04-07 | 초판 작성 |
| 2026-04-21 | Phase J (Audio UX) 반영 — §3.3 OutgoingCallScreen에 Ringback tone 필수 요소, §3.5 종료 사유 표에 Audio 컬럼 + busy tone 재생 규칙, §6 PR 체크리스트에 AudioPlayer 소유/wipe 4항목 추가. 상세 Phase 8.2 §26. |
