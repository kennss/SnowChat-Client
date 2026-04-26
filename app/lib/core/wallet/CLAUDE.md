# core/wallet — 개발 원칙

> 이 문서는 프로젝트 루트 `CLAUDE.md`를 상속하며, 상세 규칙은 `app/lib/features/wallet/CLAUDE.md`와 **동일하게 적용**된다. 본 문서는 `core/wallet` 한정 보충 사항만 명시한다.
>
> **레퍼런스**: `Documentation/Dev-plan2/Phase6-Wallet-Rebuild.md`

---

## 1. 위치와 책임

`app/lib/core/wallet/`는 지갑의 **코어 로직 계층**이다. UI/Provider에 의존하지 않고, 순수 로직만 담는다.

| 파일 | 책임 |
|------|------|
| `wallet_manager.dart` | 키페어 생명주기 (생성/로드/삭제), 니모닉↔키페어 변환 |
| `solana_client.dart` | `RpcClient` 래퍼, RPC 호출 단일 진입점 |
| `solana_config.dart` | `SolanaNetwork` enum, 엔드포인트 상수 |
| `transaction_builder.dart` | `Message` / `Instruction` 빌딩 |
| `token_service.dart` | SPL 토큰 계정 / ATA / 잔액 |
| `nft_service.dart` | NFT 메타데이터 / 소유권 조회 |

---

## 2. 의존성 방향 (엄수)

```
features/wallet/  ──▶  core/wallet/  ──▶  solana 패키지 / flutter_secure_storage
```

- **`core/wallet`는 `features/`를 import 금지** (역방향 금지).
- **`core/wallet`는 Riverpod Provider/Notifier를 정의하지 않는다.** Provider는 `features/wallet/providers/`에 둔다. core는 평범한 클래스/함수만 export.
- UI 위젯, `BuildContext`, `ref` 인자를 받지 않는다.

---

## 3. 절대 원칙 (재확인)

루트 `CLAUDE.md` 및 `features/wallet/CLAUDE.md`의 모든 규칙이 그대로 적용된다. 특히 core 계층에서 자주 위반되기 쉬운 항목:

- **BigInt only** — 함수 시그니처의 금액 파라미터는 `BigInt`. `int`/`double` 금지. `solana` 패키지 호출 직전에만 `lamports.toInt()` 허용.
- **Zero-Knowledge** — 니모닉/개인키/시드는 함수 반환 타입으로 노출 최소화. 로깅 절대 금지. 외부로 나가는 값은 공개키/주소/서명만.
- **flutter_secure_storage 단일 출처** — 키 자료 read/write는 `wallet_manager.dart`(또는 전용 SecureStorageService)로 일원화. 다른 core 파일에서 직접 접근 금지.
- **키 파생 경로 고정** — Solana `m/44'/501'/0'/0'`, SnowChat ID `m/1918'/0'`. 변경 금지.
- **하드코딩 금지** — RPC URL은 `solana_config.dart`의 `SolanaNetwork`에서만. mint/주소 상수를 다른 파일에 박지 말 것.
- **Mock 금지** — 테스트용 하드코딩 잔액·트랜잭션 금지. 통합 테스트는 Devnet 실 RPC 사용.
- **`solana` 패키지 사용** — 자체 HTTP RPC 래퍼를 새로 만들지 말 것. `RpcClient`/`Ed25519HDKeyPair`/`SystemInstruction`/`TokenInstruction`/`AssociatedTokenAccountInstruction` 사용.
- **`pinenacl` 사용 금지** — 지갑 키 서명/파생에 `pinenacl`을 쓰지 않는다 (`pinenacl`은 E2EE 모듈 전용).
- **`ed25519_hd_key` 사용 금지** — `solana` 패키지로 통일.

---

## 4. 트랜잭션 / RPC 규약

- `transaction_builder.dart`는 항상 `Message(instructions: [...])` 패턴.
- SPL 전송 빌더는 **수신자 ATA 존재 여부 확인 → 미존재 시 `AssociatedTokenAccountInstruction.createAssociatedTokenAccount` 자동 추가**.
- RPC 호출 후 `waitForSignatureStatus(confirmed)`까지 책임지는 것은 `solana_client.dart`의 헬퍼이거나, 호출자(features 계층)에서 명시적으로 await. fire-and-forget 금지.
- 생체 인증(`local_auth`)은 features 계층 책임. core는 인증을 가정하고 동작.

---

## 5. PR 체크리스트 (core 한정)

- [ ] 새 함수에 `double`/`float` 금액 파라미터가 없는가
- [ ] `core/wallet`에서 `features/`를 import 하지 않는가
- [ ] Riverpod Provider/Notifier를 정의하지 않았는가 (정의는 features/wallet/providers/)
- [ ] 키 자료가 `wallet_manager`(또는 SecureStorageService) 외부 함수에서 직접 접근되지 않는가
- [ ] RPC URL / mint / 테스트 주소를 하드코딩하지 않았는가
- [ ] 파일 헤더(@file/@description/@author=Kennt Kim/@company=Calida Lab/@created/@lastUpdated/@functions) 갱신
- [ ] `// TODO` 작성 시 `Documentation/TO-DO/<파일명>.md` 동시 작성

---

## 6. 참고

- `app/lib/features/wallet/CLAUDE.md` — 상위 모듈 원칙(상속), 금지 패턴 빠른 참조표
- `Documentation/Dev-plan2/Phase6-Wallet-Rebuild.md` — 구현 상세, 코드 예제
- 프로젝트 루트 `CLAUDE.md` — 공통 규칙
