# Wallet 모듈 — 개발 원칙

> 이 문서는 프로젝트 루트 `CLAUDE.md`를 **상속**한다. 루트 규칙(파일 헤더, 작성자, 하드코딩 금지, Zero-Knowledge, TODO 관리 등)은 그대로 적용되며, 본 문서는 지갑(Wallet) 모듈 한정 추가 원칙을 명시한다.
>
> **레퍼런스**: `Documentation/Dev-plan2/Phase6-Wallet-Rebuild.md`
> **UI 참조**: Phantom Wallet
> **로직 참조**: Espresso Cash (`solana: ^0.30.4`, Apache-2.0)

---

## 1. 모듈 범위

| 폴더 | 역할 |
|------|------|
| `app/lib/features/wallet/` | UI 화면, Provider, 기능별 서비스 (screens / providers / rpc / token / transaction / price / core / utils / widgets) |
| `app/lib/core/wallet/` | 코어 로직 (keypair, RPC client, transaction builder, token/NFT service) |

UI 화면(`screens/`)은 **수정 금지**. Provider 연결만 교체하여 로직을 새 아키텍처로 이전한다 (Phase6 §11).

---

## 2. 절대 원칙 (위반 금지)

### 2.1 BigInt Only — 금액 연산
- 앱 내부 모든 금액 변수는 **`BigInt` (lamports / 최소 단위)**.
- `double`, `float`, `num`로 금액을 다루는 코드는 **즉시 거부**.
- `int`는 **`solana` 패키지 API 호출 경계**에서만 `lamports.toInt()` 형태로 허용. 그 외 내부 변수/연산은 금지.
- 표시(UI)용 변환은 `solToLamports()` / `lamportsToSolString()` / `tokenToSmallestUnit()` / `smallestUnitToDisplay()` 유틸을 통해서만 수행.
- 가격(USD 환산)은 `double` 허용하되 **표시 전용**. 가격값으로 트랜잭션·잔액 연산 금지.

```dart
// ❌ 금지
double sol = 1.5;
int lamports = (sol * 1e9).toInt();

// ✅ 허용
final BigInt lamports = solToLamports('1.5');
```

### 2.2 Zero-Knowledge — 서버 노출 금지
- 니모닉, 개인키, 시드, 파생 키는 **서버에 절대 전송/로깅 금지**.
- `debugPrint`, `print`, 로그 파일에 키 자료(개인키/니모닉/시드/SecretBox 키) 출력 금지. 공개키/주소는 가능.
- 서버에 보낼 수 있는 것: **Solana 공개키(Base58 주소)**, **트랜잭션 서명(signature)**, 사용자가 명시적으로 동의한 메타데이터.

### 2.3 키 저장소 — flutter_secure_storage 단일 출처
- 모든 키 자료는 `flutter_secure_storage` (iOS Keychain / Android Keystore)에만 저장.
- SharedPreferences, 일반 파일, drift DB에 키 저장 **금지**.
- 키 키맵(고정):
  ```
  wallet_mnemonic       → BIP39 24단어
  wallet_private_key    → Ed25519 개인키 (Base64)
  snowchat_id_key       → SnowChat ID 파생 키 (Base64)
  ```
- `signal_*` 키맵은 E2EE 모듈 소관이므로 wallet 코드에서 read/write 금지.

### 2.4 키 파생 경로 (고정 형식, account 가변)
- **Solana 지갑**: `m/44'/501'/{account}'/0'` (Phantom 호환). account index 가변:
  - `0` = Primary (영구, 삭제 불가, SnowChat identity 와 같은 mnemonic).
  - `1+` = derived sub-wallet (사용자가 추가, hide 가능).
  - `Ed25519HDKeyPair.fromSeedWithHdPath(seed, hdPath: "m/44'/501'/{account}'/0'")`.
  - 헬퍼: `DerivationService.deriveWalletKeyPairAt(mnemonic, account)` /
    `DerivationService.walletDerivationPathFor(account)`.
- **SnowChat ID**: `m/1918'/0'`. `Ed25519HDKeyPair.fromSeedWithHdPath()`. **단일** — multi-wallet 시대에도 identity 는 1개.
- **경로 형식 변경 금지** — `m/44'/501'/.../0'` 패턴 자체는 절대 임의 변경 금지 (복원 불가능). account index 만 가변.
- **next-derivation-account-index** 계산 규칙 (Multi-Wallet-Design-FINAL.md C-2): `max(visible + hidden derived indexes) + 1`. monotonic — gap 재사용 절대 금지 (Phantom 호환성 + 보안).

### 2.5 하드코딩 금지 (루트 규칙 강화)
- 지갑 주소, mint 주소, RPC URL, 토큰 메타데이터를 코드에 박지 말 것.
- RPC 엔드포인트는 `SolanaNetwork` enum / `solanaNetworkProvider`로만 접근.
- 토큰 메타데이터는 Jupiter Token List / 서버 API에서 동적 조회.
- 테스트 지갑 주소·니모닉을 소스에 커밋 금지.

### 2.6 Mock 금지 (루트 규칙 강화)
- `_mockBalance`, `_mockTokens`, `_mockTransactions` 등 가짜 데이터로 Provider를 채우지 말 것.
- 실제 RPC가 없으면 `AsyncValue.loading` / 빈 상태로 둘 것. UI 미리보기는 `AsyncValue.data(...)`를 위젯 단에서 직접 주입하는 방식만 허용.

---

## 3. 아키텍처 원칙

### 3.1 의존성 방향
```
screens/  ──watch──▶  providers/  ──use──▶  transaction/ token/ rpc/ price/  ──use──▶  core/ (keypair, secure storage)
```
- screens는 service 객체를 직접 import 금지. 반드시 Riverpod Provider 경유.
- core는 features를 import 금지(역방향 금지).

### 3.2 Riverpod 사용
- 잔액·가격·히스토리는 `FutureProvider` / `StreamProvider`. 캐시·새로고침은 `ref.invalidate()` 사용.
- `KeypairManager`, `RpcClient`, `SubscriptionClient`는 단일 Provider 인스턴스로 공유.

### 3.3 Solana 패키지 사용 규약
- `solana ^0.30.4`의 `RpcClient`, `Ed25519HDKeyPair`, `SystemInstruction`, `TokenInstruction`, `AssociatedTokenAccountInstruction`을 직접 사용. 자체 RPC HTTP 래퍼를 새로 만들지 말 것.
- `pinenacl`은 **E2EE 전용**. 지갑 키 서명·파생에는 `solana` 패키지를 사용하고 `pinenacl`로 지갑 키를 다루지 말 것 (E2EE/지갑 책임 분리).
- `ed25519_hd_key` 패키지는 신규 코드에서 사용 금지 (`solana` 패키지로 통일).

### 3.4 트랜잭션 빌딩
- 항상 `Message(instructions: [...])` 패턴. 직접 바이트 빌드 금지.
- SPL 전송은 **수신자 ATA 존재 여부 확인 후 자동 생성 instruction 추가**.
- 트랜잭션 전송 후 `waitForSignatureStatus(confirmed)`까지 await. fire-and-forget 금지.
- 모든 전송 액션은 호출 전 `local_auth` 생체 인증 게이트를 통과해야 함.

### 3.5 잔액 캐싱
- 1차: Solana RPC 직접.
- 2차: drift DB `wallet_balances` (`raw_amount TEXT` — BigInt 문자열).
- INTEGER로 `raw_amount` 저장 금지(정밀도 손실 방지).

### 3.6 네트워크 전환
- `solanaNetworkProvider`를 통해 Devnet ↔ Mainnet 전환. 직접 URL 문자열 사용 금지.
- 네트워크 전환 시 잔액 캐시 invalidate.

---

## 4. 보안 체크리스트 (PR 머지 전 확인)

- [ ] 새 코드에 `double`/`float` 금액 연산이 없는가
- [ ] 니모닉/개인키/시드를 로그·서버·SharedPreferences에 보내지 않는가
- [ ] RPC URL·토큰 mint·테스트 주소를 하드코딩하지 않았는가
- [ ] 송금 경로에 `local_auth` 게이트가 있는가
- [ ] `signAndSendTransaction` 후 confirm 대기를 하는가
- [ ] BigInt → int 변환은 `solana` 패키지 호출 경계에만 있는가
- [ ] 새 키 자료는 `flutter_secure_storage` 키맵에 등록되어 있는가
- [ ] 파일 헤더(@file/@description/@author/@company/@created/@lastUpdated/@functions) 존재 및 갱신
- [ ] `// TODO`를 남겼다면 `Documentation/TO-DO/<파일명>.md` 동시 작성

---

## 5. 금지 패턴 빠른 참조

| 금지 | 대체 |
|------|------|
| `double amount = 1.5` | `BigInt amount = solToLamports('1.5')` |
| `1.5 * 1e9` | `solToLamports('1.5')` |
| `http.post('https://api.devnet.solana.com', ...)` 직접 호출 | `ref.read(rpcClientProvider).xxx()` |
| `ed25519_hd_key`로 키 파생 | `Ed25519HDKeyPair.fromMnemonic()` |
| 니모닉을 `print()` / 서버 API body | 절대 금지. 화면 표시는 사용자 백업 화면에서만 |
| `_mockBalance = 1000` | 실제 RPC Provider, 또는 `AsyncValue.loading` |
| `wallet_address = 'So1...'` 하드코딩 | `walletAddressProvider` |
| transaction fire-and-forget | `await waitForSignatureStatus(confirmed)` |
| SharedPreferences에 개인키 저장 | `flutter_secure_storage` |

---

## 6. 참고 문서

- `Documentation/Dev-plan2/Phase6-Wallet-Rebuild.md` — Phase 6 본 문서 (세부 구현 코드 포함)
- `Documentation/Dev-plan/05-Espresso-Cash-Analysis.md`
- `Documentation/Dev-plan/06-Master-Development-Plan.md` §8
- 프로젝트 루트 `CLAUDE.md` — 공통 규칙 (헤더, 작성자, Zero-Knowledge, 금액 타입, TODO 관리)
