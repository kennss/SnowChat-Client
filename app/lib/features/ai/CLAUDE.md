# Phase 10: On-Device AI (Gemma 4 E2B)

## 설계 문서
`Documentation/Dev-plan2/Phase10-OnDevice-AI-PoC.md` (v2, 리뷰 2회 완료)

## 핵심 원칙

### Zero-Knowledge AI
- AI 입출력은 **절대** 소켓/HTTP로 전송 금지
- `on_device_ai_service.dart`에 `dart:io`, `package:http`, `socket` **import 금지**
- AIActionBar 결과는 메모리 only — 디스크 저장 없음
- 사용자 명시 요청만 추론 (자동 추론 금지)
- AI 입출력 `debugPrint` / `print` 금지

### E2EE 파이프라인 완전 분리
- `AiMessages` 별도 테이블 (5컬럼) — `LocalMessages` (21컬럼) 재사용 **절대 금지**
- AI방은 `Conversations` 테이블에 넣지 않음 — 채팅 목록에서 하드코딩 타일로 렌더링
- 기존 MessageDao 쿼리에 AI 메시지가 섞이면 **보안 사고**

### 듀얼 세션
- `_chatBusy` — AI 방 스트리밍 (ChatSession)
- `_toolBusy` — AIActionBar 일회성 (ToolSession)
- 싱글 `_isProcessing` 플래그 사용 **금지**

## 파일 구조

```
features/ai/
├── service/
│   ├── on_device_ai_service.dart   ← 듀얼 세션 AI 코어 (네트워크 격리)
│   └── ai_model_manager.dart       ← 모델 다운로드 + SHA-256 + WiFi 감지
├── providers/
│   └── ai_provider.dart            ← Riverpod Providers
├── screens/
│   ├── ai_chat_screen.dart         ← SnowChat AI 전용 대화 화면
│   └── ai_onboarding_screen.dart   ← 모델 다운로드 온보딩
└── widgets/
    ├── ai_action_bar.dart          ← 기존 채팅방 내 AI 도구 (메시지 ID 기반)
    └── ai_chat_tile.dart           ← 채팅 목록 최상단 타일

core/storage/tables/
└── ai_messages_table.dart          ← AI 전용 drift 테이블 (5컬럼)
```

## 의존성

```yaml
flutter_gemma: # fork + 커밋 lock (calidaLab/flutter_gemma)
connectivity_plus: ^6.0.0
crypto: ^3.0.0
```

## 구현 순서

1. `flutter_gemma` fork + 네이티브 보안 감사 + 빌드 통합
2. `ai_messages_table.dart` + drift schemaVersion 마이그레이션
3. `ai_model_manager.dart` (다운로드 + SHA-256 + WiFi 감지)
4. `on_device_ai_service.dart` 듀얼 세션
5. `ai_chat_screen.dart` (스트리밍 + drift 저장)
6. `ai_chat_tile.dart` + GoRouter + 앱 잠금 guard
7. `ai_action_bar.dart` (메시지 ID 기반)
8. 한국어 PoC 테스트

## 보안 체크리스트 (파일 완성 시마다 확인)

- [ ] `dart:io`, `package:http`, `socket` import 없음 (on_device_ai_service.dart)
- [ ] `AiMessages` ↔ `LocalMessages` / `Conversations` 교차점 제로
- [ ] AIActionBar는 `conversationId`만 받음 (평문 위젯 파라미터 금지)
- [ ] 모델 SHA-256 해시 검증 (변조 차단)
- [ ] 모델 URL 특정 커밋 해시 고정 (`/resolve/main/` 금지)
- [ ] AI 입출력 로그 출력 없음
- [ ] GoRouter guard로 앱 잠금 보호 적용

## 토큰 추정 공식

```dart
// 한국어: ~3.0 tok/char, 영어: ~0.25 tok/char
// 히스토리 예산: 4000 토큰
int estimateTokens(String text) {
  final koreanRatio = koreanChars / totalChars;
  return (totalChars * (0.25 + koreanRatio * 2.75)).ceil();
}
```

## 금지 사항

- Mock 데이터 사용 금지 (하드코딩 규칙 준수)
- `List<String> decryptedMessages` 위젯 파라미터로 평문 전달 금지
- `/resolve/main/` URL 사용 금지 (모델 다운로드)
- Float/double로 토큰 수 관리 금지 (int 사용)
- flutter_gemma 업스트림 직접 의존 금지 (반드시 fork)
