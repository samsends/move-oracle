// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0


// This module attemps to find the computational cost of native function by measuring the time
// the native takes to execute.
// Isolating the native function is tricky, so we run two functions with and without the native
// The difference in execution times is the time the native takes
// functions prefixed with __baseline do not have the natives
// Many parts of the code are written in such a way that the bytecode diffs yield exactly the
// native to be isolated

// TBD: Try objects of different sizes in natives

#[test_only]
module sui::NativesCalibrationTests {
    use sui::object::{Self, Info};

    use sui::test_scenario;
    use sui::transfer;
    use sui::event;
    use sui::tx_context;

    // Number of times to run the inner loop of tests
    // We set this value to 1 to avoid long running tests
    // But normally we want something like 1000000
    const NUM_TRIALS: u64 = 1;

    // A very basic object to be used in calls
    struct ObjectSimple has key, store, drop, copy {
    }
    // A very basic object which has an Info to be used in calls
    struct ObjectWithID has key, store{
        info: Info,
    }


    // =================================================================
    // Natives in the `event` module
    // =================================================================

    // =================================================================
    // event::emit
    // =================================================================
    // This native emits an event given an object
    // > Note: this function's execution time depends on the size of the object, however we assume
    // > a flat cost for all operations

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_event_emit() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let obj1 = ObjectSimple { };
            event::calibrate_emit(obj1);
            trials = trials - 1;
        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_event_emit__baseline() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let obj1 = ObjectSimple { };
            event::calibrate_emit_nop(obj1);
            trials = trials - 1;
        }
    }


    // =================================================================
    // Natives in the `transfer` module
    // =================================================================

    // =================================================================
    // transfer::freeze_object
    // =================================================================
    // This native freezes an object

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_transfer_freeze_object() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let obj1 = ObjectSimple { };
            transfer::calibrate_freeze_object(obj1);
            trials = trials - 1;
        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_transfer_freeze_object__baseline() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let obj1 = ObjectSimple { };
            transfer::calibrate_freeze_object_nop(obj1);
            trials = trials - 1;
        }
    }

    // =================================================================
    // transfer::share_object
    // =================================================================
    // This native shares an object

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_transfer_share_object() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let obj1 = ObjectSimple { };
            transfer::calibrate_share_object(obj1);
            trials = trials - 1;
        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_transfer_share_object__baseline() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let obj1 = ObjectSimple { };
            transfer::calibrate_share_object_nop(obj1);
            trials = trials - 1;
        }
    }

    // =================================================================
    // transfer::transfer_internal
    // =================================================================
    // This native transfers an object to an address

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_transfer_transfer_internal() {
        let trials: u64 = NUM_TRIALS;
        while (trials > 0) {
            let obj1 = ObjectSimple { };
            let addr = @0x0;
            let to_object = false;
            transfer::calibrate_transfer_internal(obj1, addr, to_object);
            trials = trials - 1;
        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_transfer_transfer_internal__baseline() {
        let trials: u64 = NUM_TRIALS;
        while (trials > 0) {
            let obj1 = ObjectSimple { };
            let addr = @0x0;
            let to_object = false;
            transfer::calibrate_transfer_internal_nop(obj1, addr, to_object);
            trials = trials - 1;
        }
    }

    // =================================================================
    // transfer::delete_child_object_internal
    // =================================================================
    // TBD


    // =================================================================
    // Natives in the `id` module
    // =================================================================

    // =================================================================
    // object::bytes_to_address
    // =================================================================
    // This native converts bytes to addresses

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_id_bytes_to_address() {
        let trials: u64 = NUM_TRIALS;
        while (trials > 0) {
            let bytes = x"3a985da74fe225b2045c172d6bd390bd855f086e";
            object::calibrate_bytes_to_address(bytes);
            trials = trials - 1;
        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_id_bytes_to_address__baseline() {
        let trials: u64 = NUM_TRIALS;
        while (trials > 0) {
            let bytes = x"3a985da74fe225b2045c172d6bd390bd855f086e";
            object::calibrate_bytes_to_address_nop(bytes);
            trials = trials - 1;
        }
    }

    // =================================================================
    // object::get_versioned_id
    // =================================================================
    // This native extracts the versioned ID from an object

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_id_get_info() {
        let trials: u64 = NUM_TRIALS;
        let sender = @0x0;
        let scenario = &mut test_scenario::begin(&sender);

        while (trials > 0) {
            let obj = ObjectWithID {info: object::new(test_scenario::ctx(scenario)) };
            object::calibrate_get_info(&obj);
            let ObjectWithID { info } = obj;
            object::delete(info);

            trials = trials - 1;

        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_id_get_info__baseline() {
        let trials: u64 = NUM_TRIALS;
        let sender = @0x0;
        let scenario = &mut test_scenario::begin(&sender);

        while (trials > 0) {
            let obj = ObjectWithID {info: object::new(test_scenario::ctx(scenario)) };
            object::calibrate_get_info_nop(&obj);
            // This forces an immutable borrow to counter the ImmBorrowLoc in object::get_versioned_id
            let _ = &obj;
            let ObjectWithID { info } = obj;
            object::delete(info);

            trials = trials - 1;
        }
    }


    // =================================================================
    // Natives in the `tx_context` module
    // =================================================================

    // =================================================================
    // tx_context::derive_id
    // =================================================================
    // This native derives an ID from an object

    // This test function calls the native in a typical manner
    #[test]
    public entry fun test_calibrate_tx_context_derive_id() {
        let trials: u64 = NUM_TRIALS;
        while (trials > 0) {
            let tx_hash = x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532";
            let created_num: u64 = 0;
            tx_context::calibrate_derive_id(tx_hash, created_num);
            trials = trials - 1;
        }
    }
    // This test function excludes the natives
    #[test]
    public entry fun test_calibrate_tx_context_derive_id__baseline() {
        let trials: u64 = NUM_TRIALS;
        while (trials > 0) {
            let tx_hash = x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532";
            let created_num: u64 = 0;
            tx_context::calibrate_derive_id_nop(tx_hash, created_num);
            trials = trials - 1;
        }
    }


    // =================================================================
    // These calibrate the `Pop` bytecode instruction because it is needed
    // to calculate the cost of popping unused variables in baseline functions
    // =================================================================
    #[test]
    public entry fun test_calibrate_pop() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            let _k = false;
            trials = trials - 1;
        }
    }
    #[test]
    public entry fun test_calibrate_pop__baseline() {
        let trials: u64 = NUM_TRIALS;

        while (trials > 0) {
            trials = trials - 1;
        }
    }

}
