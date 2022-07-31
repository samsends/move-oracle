// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module sui::validator_tests {
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario;
    use sui::validator;
    use sui::stake::Stake;
    use sui::locked_coin::{Self, LockedCoin};
    use sui::stake;
    use std::option;

    #[test]
    fun test_validator_owner_flow() {
        let sender = @0x1;
        let scenario = &mut test_scenario::begin(&sender);
        {
            let ctx = test_scenario::ctx(scenario);

            let init_stake = coin::into_balance(coin::mint_for_testing(10, ctx));
            let validator = validator::new(
                sender,
                x"FF",
                b"Validator1",
                x"FFFF",
                init_stake,
                option::none(),
                ctx
            );
            assert!(validator::stake_amount(&validator) == 10, 0);
            assert!(validator::sui_address(&validator) == sender, 0);

            validator::destroy(validator);
        };

        // Check that after destroy, the original stake still exists.
        test_scenario::next_tx(scenario, &sender);
        {
            let stake = test_scenario::take_owned<Stake>(scenario);
            assert!(stake::value(&stake) == 10, 0);
            test_scenario::return_owned(scenario, stake);
        };
    }

    #[test]
    fun test_pending_validator_flow() {
        let sender = @0x1;
        let scenario = &mut test_scenario::begin(&sender);
        let ctx = test_scenario::ctx(scenario);
        let init_stake = coin::into_balance(coin::mint_for_testing(10, ctx));
        let validator = validator::new(
            sender,
            x"FF",
            b"Validator1",
            x"FFFF",
            init_stake,
            option::none(),
            ctx
        );

        test_scenario::next_tx(scenario, &sender);
        {
            let ctx = test_scenario::ctx(scenario);
            let new_stake = coin::into_balance(coin::mint_for_testing(30, ctx));
            validator::request_add_stake(&mut validator, new_stake, option::none(), ctx);

            assert!(validator::stake_amount(&validator) == 10, 0);
            assert!(validator::pending_stake_amount(&validator) == 30, 0);
        };

        test_scenario::next_tx(scenario, &sender);
        {
            let stake = test_scenario::take_last_created_owned<Stake>(scenario);
            let ctx = test_scenario::ctx(scenario);
            validator::request_withdraw_stake(&mut validator, &mut stake, 5, 35, ctx);
            test_scenario::return_owned(scenario, stake);
            assert!(validator::stake_amount(&validator) == 10, 0);
            assert!(validator::pending_stake_amount(&validator) == 30, 0);
            assert!(validator::pending_withdraw(&validator) == 5, 0);

            // Calling `adjust_stake` will withdraw the coin and transfer to sender.
            validator::adjust_stake(&mut validator);

            assert!(validator::stake_amount(&validator) == 35, 0);
            assert!(validator::pending_stake_amount(&validator) == 0, 0);
            assert!(validator::pending_withdraw(&validator) == 0, 0);
        };

        test_scenario::next_tx(scenario, &sender);
        {
            let withdraw = test_scenario::take_owned<LockedCoin<SUI>>(scenario);
            assert!(locked_coin::value(&withdraw) == 5, 0);
            test_scenario::return_owned(scenario, withdraw);
        };

        validator::destroy(validator);
    }
}
