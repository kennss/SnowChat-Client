//! @file        argon2.rs
//! @description Host tests of the passcode key derivation (`api::argon2id`,
//!              `ffi::snowzk_argon2id`): the RFC 9106 Argon2id vector run
//!              through the `argon2` crate the function uses (secret and
//!              associated data included), the reference implementation's
//!              Argon2id v1.3 vector run through the crate's own function and
//!              its C ABI, and the refusals.
//! @author      Kennt Kim
//! @company     Calida Lab
//! @created     2026-11-22
//! @lastUpdated 2026-11-22
//!
//! @functions
//!  - rfc9106_vector(): RFC 9106 §5.3 through argon2
//!  - reference_vector(): phc-winner-argon2 test.c, Argon2id v1.3
//!    ("password", "somesalt", t=2, m=2^16 KiB, p=1) through api + ffi
//!  - refusals(): short salt, zero passes, too little memory

use argon2::{Algorithm, Argon2, AssociatedData, ParamsBuilder, Version};
use snowchat_zkgroup::{api, ffi, ZkError, ARGON2_OUTPUT_LEN};

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[test]
fn rfc9106_vector() {
    // RFC 9106 §5.3 (Argon2id): password 32×0x01, salt 16×0x02, secret 8×0x03,
    // associated data 12×0x04, m=32 KiB, t=3, p=4, tag length 32.
    let params = ParamsBuilder::new()
        .m_cost(32)
        .t_cost(3)
        .p_cost(4)
        .output_len(32)
        .data(AssociatedData::new(&[0x04; 12]).unwrap())
        .build()
        .unwrap();
    let argon = Argon2::new_with_secret(&[0x03; 8], Algorithm::Argon2id, Version::V0x13, params)
        .unwrap();
    let mut out = [0u8; 32];
    argon.hash_password_into(&[0x01; 32], &[0x02; 16], &mut out).unwrap();
    assert_eq!(
        hex(&out),
        "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
    );
}

const REFERENCE: &str = "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7";

#[test]
fn reference_vector() {
    let out = api::argon2id(b"password", b"somesalt", 1 << 16, 2, 1).unwrap();
    assert_eq!(out.len(), ARGON2_OUTPUT_LEN);
    assert_eq!(hex(&out), REFERENCE);

    // The same through the C ABI.
    let password = b"password";
    let salt = b"somesalt";
    unsafe {
        let buffer = ffi::snowzk_argon2id(
            password.as_ptr(),
            password.len(),
            salt.as_ptr(),
            salt.len(),
            1 << 16,
            2,
            1,
        );
        assert_eq!(buffer.status, 0);
        let bytes = std::slice::from_raw_parts(buffer.ptr, buffer.len).to_vec();
        ffi::snowzk_free(buffer);
        assert_eq!(hex(&bytes), REFERENCE);
    }
}

#[test]
fn refusals() {
    // Salt shorter than 8 bytes.
    assert_eq!(api::argon2id(b"pw", b"short", 1024, 1, 1), Err(ZkError::InvalidInput));
    // Zero passes.
    assert_eq!(api::argon2id(b"pw", b"somesalt", 1024, 0, 1), Err(ZkError::InvalidInput));
    // Memory below 8 KiB per lane.
    assert_eq!(api::argon2id(b"pw", b"somesalt", 8, 1, 4), Err(ZkError::InvalidInput));
    // The C ABI reports the same code and no buffer.
    unsafe {
        let buffer = ffi::snowzk_argon2id(b"pw".as_ptr(), 2, b"short".as_ptr(), 5, 1024, 1, 1);
        assert_eq!(buffer.status, ZkError::InvalidInput as i32);
        assert!(buffer.ptr.is_null());
    }
}
