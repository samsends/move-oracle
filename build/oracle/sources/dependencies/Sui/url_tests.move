// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module sui::url_tests {
    use sui::url;
    use std::ascii::Self;

    const EHASH_LENGTH_MISMATCH: u64 = 0;
    const URL_STRING_MISMATCH: u64 = 1;

    #[test]
    fun test_basic_url() {
        // url strings are not currently validated
        let url_str = ascii::string(x"414243454647");

        let url = url::new_unsafe(url_str);
        assert!(url::inner_url(&url) == url_str, URL_STRING_MISMATCH);
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_malformed_hash() {
        // url strings are not currently validated
        let url_str = ascii::string(x"414243454647");
        // length too short
        let hash = x"badf012345";

        let url = url::new_unsafe(url_str);
        let _ = url::new_unsafe_url_commitment(url, hash);
    }

    #[test]
    fun test_good_hash() {
        // url strings are not currently validated
        let url_str = ascii::string(x"414243454647");
        // 32 bytes
        let hash = x"1234567890123456789012345678901234567890abcdefabcdefabcdefabcdef";

        let url = url::new_unsafe(url_str);
        let url_commit = url::new_unsafe_url_commitment(url, hash);

        assert!(url::url_commitment_resource_hash(&url_commit) == hash, EHASH_LENGTH_MISMATCH);
        assert!(url::url_commitment_inner_url(&url_commit) == url_str, URL_STRING_MISMATCH);

        let url_str = ascii::string(x"37414243454647");

        url::url_commitment_update(&mut url_commit, url_str);
        assert!(url::url_commitment_inner_url(&url_commit) == url_str, URL_STRING_MISMATCH);
    }
}
