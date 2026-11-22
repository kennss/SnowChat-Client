//! @file        lib.rs
//! @description The CLIENT role of SnowChat group protocol v2's anonymous
//!              credentials, as byte-in / byte-out functions over libsignal's
//!              `zkgroup` crate:
//!                - group id + public params from a group master key
//!                - member ciphertext <-> account id
//!                - receive an auth credential issued WITHOUT a PNI, and
//!                  present it for a group
//!                - verify a group-send-endorsements response into per-member
//!                  endorsements, and combine any subset into a send token
//!              `api` is safe Rust (used by the tests); `ffi` is the narrow C
//!              ABI that Dart binds with dart:ffi.
//! @author      Kennt Kim
//! @company     Calida Lab
//! @created     2026-11-12
//! @lastUpdated 2026-11-22 (api::argon2id / ffi::snowzk_argon2id: the app passcode's key derivation,
//!              Argon2id RFC 9106 through RustCrypto `argon2` — the one native primitive
//!              outside zkgroup)
//!
//! @functions
//!  - api::group_params(master_key): group id (32) ‖ serialized public params
//!  - api::encrypt_member(master_key, account_id): member ciphertext (65)
//!  - api::decrypt_member(master_key, ciphertext): account id (16)
//!  - api::receive_auth_credential(...): verify the server response
//!  - api::present_auth_credential(...): presentation bytes for a group
//!  - api::receive_endorsements(...): expiration (u64 BE) ‖ one endorsement
//!    (33) per member, in the caller's member order
//!  - api::send_token(master_key, endorsements, expiration): full send token
//!  - api::argon2id(password, salt, m_cost, t_cost, p_cost): 32-byte key
//!    (Argon2id v1.3, RFC 9106) — the app passcode's key derivation
//!  - ffi::snowzk_*: C ABI wrappers (see `ffi` for the buffer convention)
//!
//! @notes
//!  - Account id = the 16 bytes behind a SnowChat snowId ("snow" + 32 hex),
//!    used directly as the ACI UUID. No PNI exists; the credential uses
//!    libsignal's without-PNI variant and a per-account salt.
//!  - Timestamps are epoch SECONDS (zkgroup::Timestamp).
//!  - The group id is derived from the master key. It is also carried inside
//!    the public params, but nothing binds it to the keys there, so callers
//!    must take it from here and never from a server-supplied value.
//!  - Endorsement verification always uses libsignal's single-threaded path:
//!    on phones the thread pool only pays off above a few hundred members,
//!    and the cost is paid once per roster change, not per message.
//!  - Nothing here logs; errors carry no key material. Result buffers are
//!    zeroed when they are returned through `snowzk_free`.

use libsignal_core::{Aci, ServiceId};
use zkgroup::auth::{AnyAuthCredentialPresentation, AuthCredentialWithPni, AuthCredentialWithPniResponse};
use zkgroup::groups::{
    GroupMasterKey, GroupSecretParams, GroupSendEndorsement, GroupSendEndorsementsResponse,
    UuidCiphertext,
};
use zkgroup::{RandomnessBytes, ServerPublicParams, Timestamp, GROUP_MASTER_KEY_LEN, RANDOMNESS_LEN};

/// Length of an account id (the UUID bytes of the ACI).
pub const ACCOUNT_ID_LEN: usize = 16;

/// Length of a group id.
pub const GROUP_ID_LEN: usize = zkgroup::GROUP_IDENTIFIER_LEN;

/// Length of a serialized member ciphertext.
pub const MEMBER_CIPHERTEXT_LEN: usize = 65;

/// Length of one serialized (compressed) endorsement.
pub const ENDORSEMENT_LEN: usize = 33;

/// Length of the key [`api::argon2id`] derives.
pub const ARGON2_OUTPUT_LEN: usize = 32;

/// Shortest salt [`api::argon2id`] accepts (RFC 9106 recommends 16).
pub const ARGON2_MIN_SALT_LEN: usize = 8;

/// Why a call failed. Deliberately coarse: callers branch on the kind, and no
/// variant carries input bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum ZkError {
    /// An argument has the wrong length or cannot be parsed.
    InvalidInput = 1,
    /// A proof / credential / endorsement / ciphertext did not verify.
    VerificationFailed = 2,
    /// libsignal panicked (a caller mistake it asserts on). FFI only.
    Internal = 3,
}

pub mod api {
    use super::*;

    fn master_key(bytes: &[u8]) -> Result<GroupSecretParams, ZkError> {
        let array: [u8; GROUP_MASTER_KEY_LEN] =
            bytes.try_into().map_err(|_| ZkError::InvalidInput)?;
        Ok(GroupSecretParams::derive_from_master_key(GroupMasterKey::new(array)))
    }

    fn account(bytes: &[u8]) -> Result<Aci, ZkError> {
        let array: [u8; ACCOUNT_ID_LEN] = bytes.try_into().map_err(|_| ZkError::InvalidInput)?;
        Ok(Aci::from_uuid_bytes(array))
    }

    fn accounts(packed: &[u8]) -> Result<Vec<ServiceId>, ZkError> {
        if packed.is_empty() || packed.len() % ACCOUNT_ID_LEN != 0 {
            return Err(ZkError::InvalidInput);
        }
        packed
            .chunks_exact(ACCOUNT_ID_LEN)
            .map(|chunk| account(chunk).map(ServiceId::from))
            .collect()
    }

    fn server_public(bytes: &[u8]) -> Result<ServerPublicParams, ZkError> {
        zkgroup::deserialize::<ServerPublicParams>(bytes).map_err(|_| ZkError::InvalidInput)
    }

    fn randomness() -> RandomnessBytes {
        let mut bytes = [0u8; RANDOMNESS_LEN];
        rand::fill(&mut bytes);
        bytes
    }

    /// Group id (32 bytes) followed by the serialized public params of the
    /// group behind `master_key`. The public params are what the server stores
    /// and verifies presentations against.
    pub fn group_params(master_key_bytes: &[u8]) -> Result<Vec<u8>, ZkError> {
        let group = master_key(master_key_bytes)?;
        let mut out = group.get_group_identifier().to_vec();
        out.extend_from_slice(&zkgroup::serialize(&group.get_public_params()));
        Ok(out)
    }

    /// Deterministic per-group ciphertext of an account id — the member entry
    /// the server stores and compares presentations against.
    pub fn encrypt_member(master_key_bytes: &[u8], account_id: &[u8]) -> Result<Vec<u8>, ZkError> {
        let group = master_key(master_key_bytes)?;
        let service_id: ServiceId = account(account_id)?.into();
        Ok(zkgroup::serialize(&group.encrypt_service_id(service_id)))
    }

    /// The account id inside a member ciphertext of this group. Fails with
    /// `VerificationFailed` when the ciphertext does not belong to this group
    /// or does not hold an account id (a PNI ciphertext is never a member).
    pub fn decrypt_member(master_key_bytes: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>, ZkError> {
        let group = master_key(master_key_bytes)?;
        if ciphertext.len() != MEMBER_CIPHERTEXT_LEN {
            return Err(ZkError::InvalidInput);
        }
        let ciphertext = zkgroup::deserialize::<UuidCiphertext>(ciphertext)
            .map_err(|_| ZkError::InvalidInput)?;
        match group.decrypt_service_id(ciphertext) {
            Ok(ServiceId::Aci(aci)) => Ok(aci.service_id_binary()),
            Ok(_) | Err(_) => Err(ZkError::VerificationFailed),
        }
    }

    /// Verifies the server's auth-credential response for `account_id` (issued
    /// without a PNI, bound to `salt` and `redemption_time`) and returns the
    /// credential to keep until that day's presentations.
    pub fn receive_auth_credential(
        server_public_params: &[u8],
        account_id: &[u8],
        salt: &[u8],
        redemption_time: u64,
        response: &[u8],
    ) -> Result<Vec<u8>, ZkError> {
        let public = server_public(server_public_params)?;
        let aci = account(account_id)?;
        let response =
            AuthCredentialWithPniResponse::new(response).map_err(|_| ZkError::InvalidInput)?;
        let credential = response
            .receive_without_pni(&public, aci, salt, Timestamp::from_epoch_seconds(redemption_time))
            .map_err(|_| ZkError::VerificationFailed)?;
        Ok(zkgroup::serialize(&credential))
    }

    /// Presentation of `credential` for the group behind `master_key`. Fresh
    /// randomness each call, so two presentations are unlinkable to each other
    /// except through the (deterministic) member ciphertext they reveal.
    pub fn present_auth_credential(
        server_public_params: &[u8],
        master_key_bytes: &[u8],
        credential: &[u8],
    ) -> Result<Vec<u8>, ZkError> {
        let public = server_public(server_public_params)?;
        let group = master_key(master_key_bytes)?;
        let credential = AuthCredentialWithPni::new(credential).map_err(|_| ZkError::InvalidInput)?;
        let presentation: AnyAuthCredentialPresentation =
            credential.present(&public, &group, randomness());
        Ok(zkgroup::serialize(&presentation))
    }

    /// Verifies the server's endorsements `response` against the caller's own
    /// view of the roster — `members`, concatenated 16-byte account ids — and
    /// returns `expiration` (u64 big-endian, epoch seconds) followed by one
    /// 33-byte endorsement per member, in the order of `members`.
    ///
    /// The response only verifies when it was issued for exactly these
    /// members, so a roster that differs from the server's is detected here.
    /// libsignal also rejects an expiration that is not day-aligned, less
    /// than two hours away, or more than seven days away from `now`.
    pub fn receive_endorsements(
        server_public_params: &[u8],
        master_key_bytes: &[u8],
        response: &[u8],
        members: &[u8],
        now: u64,
    ) -> Result<Vec<u8>, ZkError> {
        let public = server_public(server_public_params)?;
        let group = master_key(master_key_bytes)?;
        let member_ids = accounts(members)?;
        let response = zkgroup::deserialize::<GroupSendEndorsementsResponse>(response)
            .map_err(|_| ZkError::InvalidInput)?;
        let expiration = response.expiration();
        let received = response
            .receive_with_service_ids_single_threaded(
                member_ids,
                Timestamp::from_epoch_seconds(now),
                &group,
                &public,
            )
            .map_err(|_| ZkError::VerificationFailed)?;

        let mut out = Vec::with_capacity(8 + received.len() * ENDORSEMENT_LEN);
        out.extend_from_slice(&expiration.epoch_seconds().to_be_bytes());
        for endorsement in &received {
            let bytes = zkgroup::serialize(&endorsement.compressed);
            debug_assert_eq!(bytes.len(), ENDORSEMENT_LEN);
            out.extend_from_slice(&bytes);
        }
        Ok(out)
    }

    /// Combines `endorsements` (concatenated 33-byte endorsements, as returned
    /// by [`receive_endorsements`]) into the full send token for exactly that
    /// set of members. Combining is a set operation: order does not matter,
    /// and any subset of one response is a valid recipient set.
    ///
    /// `expiration` must be the value returned with those endorsements.
    pub fn send_token(
        master_key_bytes: &[u8],
        endorsements: &[u8],
        expiration: u64,
    ) -> Result<Vec<u8>, ZkError> {
        let group = master_key(master_key_bytes)?;
        if endorsements.is_empty() || endorsements.len() % ENDORSEMENT_LEN != 0 {
            return Err(ZkError::InvalidInput);
        }
        let points: Vec<GroupSendEndorsement> = endorsements
            .chunks_exact(ENDORSEMENT_LEN)
            .map(|chunk| {
                zkgroup::deserialize::<GroupSendEndorsement>(chunk)
                    .map_err(|_| ZkError::InvalidInput)
            })
            .collect::<Result<_, _>>()?;
        let combined = GroupSendEndorsement::combine(points);
        Ok(zkgroup::serialize(
            &combined
                .to_token(&group)
                .into_full_token(Timestamp::from_epoch_seconds(expiration)),
        ))
    }

    /// Argon2id v1.3 (RFC 9106) of `password` with `salt`: a 32-byte key.
    /// `m_cost` is the memory in KiB, `t_cost` the passes, `p_cost` the lanes.
    /// No secret, no associated data. Parameters argon2 refuses (memory below
    /// 8 × lanes, zero passes or lanes, a salt shorter than
    /// [`ARGON2_MIN_SALT_LEN`]) are `InvalidInput`.
    pub fn argon2id(
        password: &[u8],
        salt: &[u8],
        m_cost: u32,
        t_cost: u32,
        p_cost: u32,
    ) -> Result<Vec<u8>, ZkError> {
        use argon2::{Algorithm, Argon2, Params, Version};
        if salt.len() < ARGON2_MIN_SALT_LEN {
            return Err(ZkError::InvalidInput);
        }
        let params = Params::new(m_cost, t_cost, p_cost, Some(ARGON2_OUTPUT_LEN))
            .map_err(|_| ZkError::InvalidInput)?;
        let mut out = vec![0u8; ARGON2_OUTPUT_LEN];
        Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
            .hash_password_into(password, salt, &mut out)
            .map_err(|_| ZkError::InvalidInput)?;
        Ok(out)
    }
}

/// C ABI.
///
/// Convention (one for every function): inputs are `(pointer, length)` pairs
/// that the callee only reads; the result is a [`ZkBuffer`]. On success
/// `status == 0` and `ptr/len` describe a heap buffer the caller MUST return
/// with [`snowzk_free`], which zeroes it before releasing it. On failure
/// `status` is a [`ZkError`] value and `ptr` is null. A panic inside
/// libsignal is caught and reported as `ZkError::Internal` — it never unwinds
/// into the caller.
pub mod ffi {
    use super::*;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use zeroize::Zeroize;

    #[repr(C)]
    pub struct ZkBuffer {
        pub ptr: *mut u8,
        pub len: usize,
        pub status: i32,
    }

    impl ZkBuffer {
        fn ok(bytes: Vec<u8>) -> Self {
            let mut boxed = bytes.into_boxed_slice();
            let buffer = ZkBuffer { ptr: boxed.as_mut_ptr(), len: boxed.len(), status: 0 };
            std::mem::forget(boxed);
            buffer
        }

        fn err(error: ZkError) -> Self {
            ZkBuffer { ptr: std::ptr::null_mut(), len: 0, status: error as i32 }
        }
    }

    /// # Safety
    /// `ptr` must be valid for reads of `len` bytes, or `len` must be 0.
    unsafe fn slice<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
        if len == 0 || ptr.is_null() {
            &[]
        } else {
            std::slice::from_raw_parts(ptr, len)
        }
    }

    fn run(call: impl FnOnce() -> Result<Vec<u8>, ZkError>) -> ZkBuffer {
        match catch_unwind(AssertUnwindSafe(call)) {
            Ok(Ok(bytes)) => ZkBuffer::ok(bytes),
            Ok(Err(error)) => ZkBuffer::err(error),
            Err(_) => ZkBuffer::err(ZkError::Internal),
        }
    }

    /// Zeroes and releases a buffer returned by any `snowzk_*` function.
    /// Results include credentials and endorsements, so they are not left in
    /// freed heap memory.
    ///
    /// # Safety
    /// `buffer` must come from this library and be freed at most once.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_free(buffer: ZkBuffer) {
        if !buffer.ptr.is_null() {
            let mut boxed = Box::from_raw(std::ptr::slice_from_raw_parts_mut(buffer.ptr, buffer.len));
            boxed.zeroize();
            drop(boxed);
        }
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_group_params(
        master_key: *const u8,
        master_key_len: usize,
    ) -> ZkBuffer {
        let master_key = slice(master_key, master_key_len);
        run(|| api::group_params(master_key))
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_encrypt_member(
        master_key: *const u8,
        master_key_len: usize,
        account_id: *const u8,
        account_id_len: usize,
    ) -> ZkBuffer {
        let master_key = slice(master_key, master_key_len);
        let account_id = slice(account_id, account_id_len);
        run(|| api::encrypt_member(master_key, account_id))
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_decrypt_member(
        master_key: *const u8,
        master_key_len: usize,
        ciphertext: *const u8,
        ciphertext_len: usize,
    ) -> ZkBuffer {
        let master_key = slice(master_key, master_key_len);
        let ciphertext = slice(ciphertext, ciphertext_len);
        run(|| api::decrypt_member(master_key, ciphertext))
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_receive_auth_credential(
        server_public_params: *const u8,
        server_public_params_len: usize,
        account_id: *const u8,
        account_id_len: usize,
        salt: *const u8,
        salt_len: usize,
        redemption_time: u64,
        response: *const u8,
        response_len: usize,
    ) -> ZkBuffer {
        let server_public_params = slice(server_public_params, server_public_params_len);
        let account_id = slice(account_id, account_id_len);
        let salt = slice(salt, salt_len);
        let response = slice(response, response_len);
        run(|| {
            api::receive_auth_credential(
                server_public_params,
                account_id,
                salt,
                redemption_time,
                response,
            )
        })
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_present_auth_credential(
        server_public_params: *const u8,
        server_public_params_len: usize,
        master_key: *const u8,
        master_key_len: usize,
        credential: *const u8,
        credential_len: usize,
    ) -> ZkBuffer {
        let server_public_params = slice(server_public_params, server_public_params_len);
        let master_key = slice(master_key, master_key_len);
        let credential = slice(credential, credential_len);
        run(|| api::present_auth_credential(server_public_params, master_key, credential))
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_receive_endorsements(
        server_public_params: *const u8,
        server_public_params_len: usize,
        master_key: *const u8,
        master_key_len: usize,
        response: *const u8,
        response_len: usize,
        members: *const u8,
        members_len: usize,
        now: u64,
    ) -> ZkBuffer {
        let server_public_params = slice(server_public_params, server_public_params_len);
        let master_key = slice(master_key, master_key_len);
        let response = slice(response, response_len);
        let members = slice(members, members_len);
        run(|| api::receive_endorsements(server_public_params, master_key, response, members, now))
    }

    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_send_token(
        master_key: *const u8,
        master_key_len: usize,
        endorsements: *const u8,
        endorsements_len: usize,
        expiration: u64,
    ) -> ZkBuffer {
        let master_key = slice(master_key, master_key_len);
        let endorsements = slice(endorsements, endorsements_len);
        run(|| api::send_token(master_key, endorsements, expiration))
    }

    /// Argon2id of a passcode: see [`api::argon2id`]. The 32-byte result is
    /// key material — the caller frees it with [`snowzk_free`], which zeroes
    /// it.
    ///
    /// # Safety
    /// See the module convention.
    #[no_mangle]
    pub unsafe extern "C" fn snowzk_argon2id(
        password: *const u8,
        password_len: usize,
        salt: *const u8,
        salt_len: usize,
        m_cost: u32,
        t_cost: u32,
        p_cost: u32,
    ) -> ZkBuffer {
        let password = slice(password, password_len);
        let salt = slice(salt, salt_len);
        run(|| api::argon2id(password, salt, m_cost, t_cost, p_cost))
    }
}
