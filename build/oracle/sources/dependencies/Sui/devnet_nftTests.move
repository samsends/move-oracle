// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A minimalist example to demonstrate how to create an NFT like object
/// on Sui. The user should be able to use the wallet command line tool
/// (https://docs.sui.io/build/wallet) to mint an NFT. For example,
/// `wallet example-nft --name <Name> --description <Description> --url <URL>`
module sui::devnet_nft {
    use sui::url::{Self, Url};
    use sui::utf8;
    use sui::object::{Self, ID, Info};
    use sui::event;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    /// An example NFT that can be minted by anybody
    struct DevNetNFT has key, store {
        info: Info,
        /// Name for the token
        name: utf8::String,
        /// Description of the token
        description: utf8::String,
        /// URL for the token
        url: Url,
        // TODO: allow custom attributes
    }

    struct MintNFTEvent has copy, drop {
        // The Object ID of the NFT
        object_id: ID,
        // The creator of the NFT
        creator: address,
        // The name of the NFT
        name: utf8::String,
    }

    /// Create a new devnet_nft
    public entry fun mint(
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let nft = DevNetNFT {
            info: object::new(ctx),
            name: utf8::string_unsafe(name),
            description: utf8::string_unsafe(description),
            url: url::new_unsafe_from_bytes(url)
        };
        let sender = tx_context::sender(ctx);
        event::emit(MintNFTEvent {
            object_id: *object::info_id(&nft.info),
            creator: sender,
            name: nft.name,
        });
        transfer::transfer(nft, sender);
    }

    /// Transfer `nft` to `recipient`
    public entry fun transfer(
        nft: DevNetNFT, recipient: address, _: &mut TxContext
    ) {
        transfer::transfer(nft, recipient)
    }

    /// Update the `description` of `nft` to `new_description`
    public entry fun update_description(
        nft: &mut DevNetNFT,
        new_description: vector<u8>,
        _: &mut TxContext
    ) {
        nft.description = utf8::string_unsafe(new_description)
    }

    /// Permanently delete `nft`
    public entry fun burn(nft: DevNetNFT, _: &mut TxContext) {
        let DevNetNFT { info, name: _, description: _, url: _ } = nft;
        object::delete(info)
    }

    /// Get the NFT's `name`
    public fun name(nft: &DevNetNFT): &utf8::String {
        &nft.name
    }

    /// Get the NFT's `description`
    public fun description(nft: &DevNetNFT): &utf8::String {
        &nft.description
    }

    /// Get the NFT's `url`
    public fun url(nft: &DevNetNFT): &Url {
        &nft.url
    }
}

#[test_only]
module sui::devnet_nftTests {
    use sui::devnet_nft::{Self, DevNetNFT};
    use sui::test_scenario;
    use sui::utf8;

    #[test]
    fun mint_transfer_update() {
        let addr1 = @0xA;
        let addr2 = @0xB;
        // create the NFT
        let scenario = test_scenario::begin(&addr1);
        {
            devnet_nft::mint(b"test", b"a test", b"https://www.sui.io", test_scenario::ctx(&mut scenario))
        };
        // send it from A to B
        test_scenario::next_tx(&mut scenario, &addr1);
        {
            let nft = test_scenario::take_owned<DevNetNFT>(&mut scenario);
            devnet_nft::transfer(nft, addr2, test_scenario::ctx(&mut scenario));
        };
        // update its description
        test_scenario::next_tx(&mut scenario, &addr2);
        {
            let nft = test_scenario::take_owned<DevNetNFT>(&mut scenario);
            devnet_nft::update_description(&mut nft, b"a new description", test_scenario::ctx(&mut scenario)) ;
            assert!(*utf8::bytes(devnet_nft::description(&nft)) == b"a new description", 0);
            test_scenario::return_owned(&mut scenario, nft);
        };
        // burn it
        test_scenario::next_tx(&mut scenario, &addr2);
        {
            let nft = test_scenario::take_owned<DevNetNFT>(&mut scenario);
            devnet_nft::burn(nft, test_scenario::ctx(&mut scenario))
        }
    }
}
