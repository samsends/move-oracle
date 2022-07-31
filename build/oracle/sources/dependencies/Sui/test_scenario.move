// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module sui::test_scenario {
    use sui::object::{Self, ID, Info};
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    use std::vector;

    /// Requested a transfer or user-defined event on an invalid transaction index
    const EInvalidTxIndex: u64 = 1;

    /// Attempted to return an object to the inventory that was not previously removed from the
    /// inventory during the current transaction. Can happen if the user attempts to call
    /// `return_owned` on a locally constructed object rather than one returned from a `test_scenario`
    /// function such as `take_owned`.
    const ECantReturnObject: u64 = 2;

    /// Attempted to retrieve an object of a particular type from the inventory, but it is empty.
    /// Can happen if the user already transferred the object or a previous transaction failed to
    /// transfer the object to the user.
    const EEmptyInventory: u64 = 3;

    /// Expected 1 object of this type in the tx sender's inventory, but found >1.
    /// Consider using test_scenario::take_owned_by_id to select a specific object
    const EInventoryAmbiguity: u64 = 4;

    /// The inventory previously contained an object of this type, but it was removed during the current
    /// transaction.
    const EAlreadyRemovedObject: u64 = 5;

    /// Object of given ID cannot be found in the inventory.
    const EObjectIDNotFound: u64 = 6;

    /// Utility for mocking a multi-transaction Sui execution in a single Move procedure.
    /// A `Scenario` maintains a view of the global object pool built up by the execution.
    /// These objects can be accessed via functions like `take_owned`, which gives the
    /// transaction sender access to (only) objects in their inventory.
    /// Example usage:
    /// ```
    /// let addr1: address = 0;
    /// let addr2: address = 1;
    /// // begin a test scenario in a context where addr1 is the sender
    /// let scenario = &mut test_scenario::begin(&addr1);
    /// // addr1 sends an object to addr2
    /// {
    ///     let some_object: SomeObject = ... // construct an object
    ///     transfer::transfer(some_object, copy addr2)
    /// };
    /// // end the first transaction and begin a new one where addr2 is the sender
    /// test_scenario::next_tx(scenario, &addr2)
    /// {
    ///     // remove the SomeObject value from addr2's inventory
    ///     let obj = test_scenario::take_owned<SomeObject>(scenario);
    ///     // use it to test some function that needs this value
    ///     SomeObject::some_function(obj)
    /// }
    /// ... // more txes
    /// ```
    struct Scenario has drop {
        ctx: TxContext,
        /// Object ID's that have been removed during the current transaction. Needed to prevent
        /// double removals
        removed: vector<ID>,
        /// The `i`th entry in this vector is the start index for events emitted by the `i`th transaction.
        /// This information allows us to partition events emitted by distinct transactions
        event_start_indexes: vector<u64>,
    }

    /// A wrapper for test_scenario to return an immutable object from the inventory
    struct ImmutableWrapper<T: key> {
        object: T,
    }

    /// A wrapper for test_scenario to return a shared object from the inventory
    struct SharedWrapper<T: key> {
        object: T,
    }

    /// Begin a new multi-transaction test scenario in a context where `sender` is the tx sender
    public fun begin(sender: &address): Scenario {
        Scenario {
            ctx: tx_context::new_from_hint(*sender, 0, 0, 0),
            removed: vector::empty(),
            event_start_indexes: vector[0],
        }
    }

    /// Advance the scenario to a new transaction where `sender` is the transaction sender
    public fun next_tx(scenario: &mut Scenario, sender: &address) {
        let last_tx_start_index = last_tx_start_index(scenario);
        let old_total_events = last_tx_start_index;

        // Objects that were wrapped during the transaction need to be explicitly handled
        // since there is no dedicated event for object wrapping.
        // We know an object was wrapped if:
        // - it was removed and not returned
        // - it does not appear in an event during the current transaction.
        emit_wrapped_object_events(last_tx_start_index, &scenario.removed);
        // reset `removed` for the next tx
        scenario.removed = vector::empty();

        // start index for the next tx is the end index for the current one
        let new_total_events = num_events();
        let tx_event_count = new_total_events - old_total_events;
        let event_end_index = last_tx_start_index + tx_event_count;
        vector::push_back(&mut scenario.event_start_indexes, event_end_index);

        // create a seed for new transaction digest to ensure that this tx has a different
        // digest (and consequently, different object ID's) than the previous tx
        let new_tx_digest_seed = (vector::length(&scenario.event_start_indexes) as u8);
        let epoch = tx_context::epoch(&scenario.ctx);
        scenario.ctx = tx_context::new_from_hint(*sender, new_tx_digest_seed, epoch, 0);
    }

    /// Advance the scenario to a new epoch.
    public fun next_epoch(scenario: &mut Scenario) {
        tx_context::increment_epoch_number(&mut scenario.ctx);
    }

    /// Remove the object of type `T` from the inventory of the current tx sender in `scenario`.
    /// An object is in the sender's inventory if:
    /// - The object is in the global event log
    /// - The sender owns the object
    /// - If the object was previously removed, it was subsequently replaced via a call to `return_owned`.
    /// Aborts if there is no object of type `T` in the inventory of the tx sender
    /// Aborts if there is >1 object of type `T` in the inventory of the tx sender--this function
    /// only succeeds when the object to choose is unambiguous. In cases where there are multiple `T`'s,
    /// the caller should resolve the ambiguity by using `take_owned_by_id`.
    public fun take_owned<T: key>(scenario: &mut Scenario): T {
        let signer_address = sender(scenario);
        let objects: vector<T> = get_account_owned_inventory<T>(
            signer_address,
            last_tx_start_index(scenario)
        );
        remove_unique_object_from_inventory(scenario, objects)
    }

    /// Remove the object of type `T` from the inventory of the current tx sender in `scenario`
    /// that wast most recently created.
    /// Aborts if there is no object of type `T` in the inventory of the tx sender.
    public fun take_last_created_owned<T: key>(scenario: &mut Scenario): T {
        let signer_address = sender(scenario);
        let objects: vector<T> = get_account_owned_inventory<T>(
            signer_address,
            last_tx_start_index(scenario)
        );
        let num_objects = vector::length(&objects);
        assert!(num_objects > 0, EEmptyInventory);
        let res = vector::pop_back(&mut objects);
        let removed_id = object::id(&res);
        assert!(!vector::contains(&scenario.removed, removed_id), EAlreadyRemovedObject);
        vector::push_back(&mut scenario.removed, *removed_id);
        let i = 0;
        // Put the rest of the objects back into the storage.
        while (i < num_objects - 1) {
            update_object(vector::remove(&mut objects, 0));
            i = i + 1
        };
        vector::destroy_empty(objects);
        res
    }

    /// Similar to take_owned, but only return objects that are immutable with type `T`.
    /// In this case, the sender is irrelevant.
    /// Returns a wrapper that only supports a `borrow` API to get the read-only reference.
    public fun take_immutable<T: key>(scenario: &mut Scenario): ImmutableWrapper<T> {
        let objects: vector<T> = get_unowned_inventory<T>(
            true /* immutable */,
            last_tx_start_index(scenario),
        );
        let object = remove_unique_object_from_inventory(scenario, objects);
        ImmutableWrapper {
            object,
        }
    }

    /// Returns the underlying reference of an immutable object wrapper returned above.
    public fun borrow<T: key>(wrapper: &ImmutableWrapper<T>): &T {
        &wrapper.object
    }

    /// Similar to take_owned, but only return objects that are shared with type `T`.
    /// In this case, the sender is irrelevant.
    /// Returns a wrapper that only supports a `borrow_mut` API to get the mutable reference.
    public fun take_shared<T: key>(scenario: &mut Scenario): SharedWrapper<T> {
        let objects: vector<T> = get_unowned_inventory<T>(
            false /* immutable */,
            last_tx_start_index(scenario),
        );
        let object = remove_unique_object_from_inventory(scenario, objects);
        SharedWrapper {
            object,
        }
    }

    /// Returns the underlying mutable reference of a shared object.
    public fun borrow_mut<T: key>(wrapper: &mut SharedWrapper<T>): &mut T {
        &mut wrapper.object
    }

    /// Remove and return the child object of type `T2` owned by `parent_obj`.
    /// Aborts if there is no object of type `T2` owned by `parent_obj`
    /// Aborts if there is >1 object of type `T2` owned by `parent_obj`--this function
    /// only succeeds when the object to choose is unambiguous. In cases where there are are multiple `T`'s
    /// owned by `parent_obj`, the caller should resolve the ambiguity using `take_child_object_by_id`.
    public fun take_child_object<T1: key, T2: key>(
        scenario: &mut Scenario, parent_obj: &T1
    ): T2 {
        let signer_address = sender(scenario);
        let objects = get_object_owned_inventory<T2>(
            signer_address,
            object::id_address(object::id(parent_obj)),
            last_tx_start_index(scenario),
        );
        remove_unique_object_from_inventory(scenario, objects)
    }

    /// Same as `take_owned`, but returns the object of type `T` with object ID `id`.
    /// Should only be used in cases where current tx sender has more than one object of
    /// type `T` in their inventory.
    public fun take_owned_by_id<T: key>(scenario: &mut Scenario, id: ID): T {
        let sender = sender(scenario);
        let inventory: vector<T> = get_account_owned_inventory<T>(
            sender,
            last_tx_start_index(scenario)
        );
        let object_opt = find_object_by_id_in_inventory(inventory, &id);
        remove_unique_object_from_inventory(scenario, option::to_vec(object_opt))
    }

    /// This function tells you whether calling `take_owned_by_id` would succeed.
    /// It provides a way to check without triggering assertions.
    public fun can_take_owned_by_id<T: key>(scenario: &Scenario, id: ID): bool {
        // Check that the object has not been removed from the inventory.
        if (vector::contains(&scenario.removed, &id)) {
            return false
        };
        let sender = sender(scenario);
        let objects: vector<T> = get_account_owned_inventory<T>(
            sender,
            last_tx_start_index(scenario)
        );
        // And the object with the specified ID is indeed one of the owned.
        let object_opt: Option<T> = find_object_by_id_in_inventory(objects, &id);
        let res =  option::is_some(&object_opt);
        drop_object_for_testing(object_opt);
        res
    }

    /// Same as `take_child_object`, but returns the child object of type `T` with object ID `id`.
    /// Should only be used in cases where the parent object has more than one child of type `T`.
    public fun take_child_object_by_id<T1: key, T2: key>(
        scenario: &mut Scenario, parent_obj: &T1, child_id: ID
    ): T2 {
        let signer_address = sender(scenario);
        let objects = get_object_owned_inventory<T2>(
            signer_address,
            object::id_address(object::id(parent_obj)),
            last_tx_start_index(scenario),
        );
        let child_object_opt = find_object_by_id_in_inventory(objects, &child_id);
        remove_unique_object_from_inventory(scenario, option::to_vec(child_object_opt))
    }

    /// Return `t` to the global object pool maintained by `scenario`.
    /// Subsequent calls to `take_owned<T>` will succeed if the object is in the inventory of the current
    /// transaction sender.
    /// Aborts if `t` was not previously taken from the inventory via a call to `take_owned` or similar.
    public fun return_owned<T: key>(scenario: &mut Scenario, t: T) {
        let id = object::id(&t);
        let removed = &mut scenario.removed;
        // TODO: add Vector::remove_element to Std that does this 3-liner
        let (is_mem, idx) = vector::index_of(removed, id);
        // can't return an object we haven't removed
        assert!(is_mem, ECantReturnObject);
        vector::remove(removed, idx);

        // Update the object content in the inventory.
        // Because the events are the source of truth for all object values in the inventory,
        // we must put any state change future txes want to see in an event. It would not be safe
        // to do (e.g.) `delete_object_for_testing(t)` instead.
        update_object(t)
    }

    /// Similar to return_owned, return a shared object to the inventory.
    public fun return_shared<T: key>(scenario: &mut Scenario, object_wrapper: SharedWrapper<T>) {
        let SharedWrapper { object } = object_wrapper;
        return_owned(scenario, object)
    }

    /// Return an immutable object to the inventory.
    public fun return_immutable<T: key>(scenario: &mut Scenario, object_wrapper: ImmutableWrapper<T>) {
        let ImmutableWrapper { object } = object_wrapper;
        return_owned(scenario, object)
    }

    /// Return `true` if a call to `take_owned<T>(scenario)` will succeed
    public fun can_take_owned<T: key>(scenario: &Scenario): bool {
        let objects: vector<T> = get_account_owned_inventory<T>(
            sender(scenario),
            last_tx_start_index(scenario)
        );
        // Check that there is one unique such object, and it has not
        // yet been removed from the inventory.
        let res = vector::length(&objects) == 1;
        if (res) {
            let id = object::id(vector::borrow(&objects, 0));
            res = !vector::contains(&scenario.removed, id);
        };
        drop_object_for_testing(objects);
        res
    }

    /// Return the `TxContext` associated with this `scenario`
    public fun ctx(scenario: &mut Scenario): &mut TxContext {
        &mut scenario.ctx
    }

    /// Generate a fresh ID for the current tx associated with this `scenario`
    public fun new_object(scenario: &mut Scenario): Info {
        object::new(&mut scenario.ctx)
    }

    /// Return the sender of the current tx in this `scenario`
    public fun sender(scenario: &Scenario): address {
        tx_context::sender(&scenario.ctx)
    }

    /// Return the number of concluded transactions in this scenario.
    /// This does not include the current transaction--e.g., this will return 0 if `next_tx` has never been called
    public fun num_concluded_txes(scenario: &Scenario): u64 {
        vector::length(&scenario.event_start_indexes) - 1
    }

    /// Return the index in the global transaction log where the events emitted by the `tx_idx`th transaction begin
    fun tx_start_index(scenario: &Scenario, tx_idx: u64): u64 {
        let idxs = &scenario.event_start_indexes;
        let len = vector::length(idxs);
        assert!(tx_idx < len, EInvalidTxIndex);
        *vector::borrow(idxs, tx_idx)
    }

    /// Return the tx start index of the current transaction. This is an index into the global event log
    /// such that all events emitted by the current transaction occur at or after this index
    fun last_tx_start_index(scenario: &Scenario): u64 {
        let idxs = &scenario.event_start_indexes;
        // Safe because because `event_start_indexes` is always non-empty
        *vector::borrow(idxs, vector::length(idxs) - 1)
    }

    fun remove_unique_object_from_inventory<T: key>(scenario: &mut Scenario, inventory: vector<T>): T {
        let objects_len = vector::length(&inventory);
        if (objects_len == 1) {
            // found a unique object. ensure that it hasn't already been removed, then return it
            let t = vector::pop_back(&mut inventory);
            let id = object::id(&t);
            vector::destroy_empty(inventory);

            assert!(!vector::contains(&scenario.removed, id), EAlreadyRemovedObject);
            vector::push_back(&mut scenario.removed, *id);
            t
        } else if (objects_len == 0) {
            abort(EEmptyInventory)
        } else { // objects_len > 1
            abort(EInventoryAmbiguity)
        }
    }

    fun find_object_by_id_in_inventory<T: key>(inventory: vector<T>, id: &ID): Option<T> {
        let object_opt = option::none();
        while (!vector::is_empty(&inventory)) {
            let element = vector::pop_back(&mut inventory);
            if (object::id(&element) == id) {
                // Within the same test scenario, there is no way to
                // create two objects with the same ID. So this should
                // be unique.
                option::fill(&mut object_opt, element);
            } else {
                drop_object_for_testing(element);
            }
        };
        vector::destroy_empty(inventory);

        object_opt
    }

    // TODO: Add API's for inspecting user events, printing the user's inventory, ...

    // ---Natives---

    /// Return all live objects of type `T` that can be accessed by `signer_address` in the current transaction
    /// Events at or beyond `tx_end_index` in the log should not be processed to build this inventory
    native fun get_account_owned_inventory<T: key>(signer_address: address, tx_end_index: u64): vector<T>;

    /// Return all live objects of type `T` that's owned by another object `parent_object_id`, with
    /// signer account `signer_address`.
    /// Events at or beyond `tx_end_index` in the log should not be processed to build this inventory
    native fun get_object_owned_inventory<T: key>(
        signer_address: address,
        parent_object_id: address,
        tx_end_index: u64,
    ): vector<T>;

    /// Return all live objects of type `T` that's not owned, i.e. either immutable or shared.
    /// `immutable` indicates whether we want to return immutable object or shared.
    /// Events at or beyond `tx_end_index` in the log should not be processed to build this inventory
    native fun get_unowned_inventory<T: key>(immutable: bool, tx_end_index: u64): vector<T>;

    /// Test-only function for dropping an arbitrary object.
    /// Useful for eliminating objects without the `drop` ability.
    /// Note that this doesn't delete the object from anywhere.
    /// Usually it existed in the first place through a native copy
    /// that could not be done in normal code path.
    native fun drop_object_for_testing<T>(t: T);

    /// Return the total number of events emitted by all txes in the current VM execution, including both user-defined events and system events
    native fun num_events(): u64;

    /// Find out all objects that were wrapped during the transaction, and emit an event for each of them.
    native fun emit_wrapped_object_events<ID>(tx_begin_idx: u64, removed: &vector<ID>);

    /// Update the content of an object in the inventory.
    native fun update_object<T: key>(obj: T);
}
