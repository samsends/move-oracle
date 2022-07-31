// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Test CTURD object basics (create, transfer, update, read, delete)
module sui::object_basics {
    use sui::event;
    use sui::object::{Self, Info};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    struct Object has key, store {
        info: Info,
        value: u64,
    }

    struct Wrapper has key {
        info: Info,
        o: Object
    }

    struct NewValueEvent has copy, drop {
        new_value: u64
    }

    public entry fun create(value: u64, recipient: address, ctx: &mut TxContext) {
        transfer::transfer(
            Object { info: object::new(ctx), value },
            recipient
        )
    }

    public entry fun transfer(o: Object, recipient: address) {
        transfer::transfer(o, recipient)
    }

    public entry fun freeze_object(o: Object) {
        transfer::freeze_object(o)
    }

    public entry fun set_value(o: &mut Object, value: u64) {
        o.value = value;
    }

    // test that reading o2 and updating o1 works
    public entry fun update(o1: &mut Object, o2: &Object) {
        o1.value = o2.value;
        // emit an event so the world can see the new value
        event::emit(NewValueEvent { new_value: o2.value })
    }

    public entry fun delete(o: Object) {
        let Object { info, value: _ } = o;
        object::delete(info);
    }

    public entry fun wrap(o: Object, ctx: &mut TxContext) {
        transfer::transfer(Wrapper { info: object::new(ctx), o }, tx_context::sender(ctx))
    }

    public entry fun unwrap(w: Wrapper, ctx: &mut TxContext) {
        let Wrapper { info, o } = w;
        object::delete(info);
        transfer::transfer(o, tx_context::sender(ctx))
    }
}
