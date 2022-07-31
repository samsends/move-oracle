// Copyright (c) 2022, oracle Protocol
// SPDX-License-Identifier: AGPL-3.0 

/// - anyone can create and share a price_component
/// - the controller of the price_component can reset it to any value
module oracle::price_component {
    use sui::tx_context::{Self, TxContext};

    /// A price_component storage object
    struct PriceComponent has store {
        controller: address,
        price: u64,
        confidence: u64,
        epoch: u64,
    }

    public fun new(controller: address): PriceComponent {
        PriceComponent {
            controller: controller,
            price: 0,
            confidence: 0,
            epoch: 0,
        }
    }

    public fun controller(price_component: &PriceComponent): address {
        price_component.controller
    }

    public fun price(price_component: &PriceComponent): u64 {
        price_component.price
    }

    public fun confidence(price_component: &PriceComponent): u64 {
        price_component.confidence
    }

    public fun epoch(price_component: &PriceComponent): u64 {
        price_component.epoch
    }

    /// Set value (only runnable by the price_component controller)
    public fun set(price_component: &mut PriceComponent, price: u64, confidence: u64, ctx: &mut TxContext) {
        assert!(price_component.controller == tx_context::sender(ctx), 0);

        price_component.price = price;
        price_component.confidence = confidence;
        price_component.epoch = tx_context::epoch(ctx);
        // TODO: get more fine-grained block time???
    }
}

// #[test_only]
// module oracle::price_component_test {
//     use sui::test_scenario;
//     use oracle::price_component;

//     #[test]
//     fun test_price_component() {
//         let controller = @0xC0FFEE;
//         let user1 = @0xA1;

//         let scenario = &mut test_scenario::begin(&user1);

//         test_scenario::next_tx(scenario, &controller);
//         {
//             price_component::create(test_scenario::ctx(scenario));
//         };

//         test_scenario::next_tx(scenario, &user1);
//         {
//             let price_component_wrapper = test_scenario::take_shared<price_component::PriceComponent>(scenario);
//             let price_component = test_scenario::borrow_mut(&mut price_component_wrapper);

//             assert!(price_component::controller(price_component) == controller, 0);
//             assert!(price_component::price(price_component) == 0, 1);
//             assert!(price_component::confidence(price_component) == 0, 1);


//             test_scenario::return_shared(scenario, price_component_wrapper);
//         };

//         test_scenario::next_tx(scenario, &controller);
//         {
//             let price_component_wrapper = test_scenario::take_shared<price_component::PriceComponent>(scenario);
//             let price_component = test_scenario::borrow_mut(&mut price_component_wrapper);

//             assert!(price_component::controller(price_component) == controller, 1);


//             price_component::set(price_component, 1, 1, test_scenario::ctx(scenario));

//             test_scenario::return_shared(scenario, price_component_wrapper);
//         };

//         test_scenario::next_tx(scenario, &user1);
//         {
//             let price_component_wrapper = test_scenario::take_shared<price_component::PriceComponent>(scenario);
//             let price_component = test_scenario::borrow_mut(&mut price_component_wrapper);

//             assert!(price_component::controller(price_component) == controller, 0);
//             assert!(price_component::price(price_component) == 1, 1);
//             assert!(price_component::confidence(price_component) == 1, 1);


//             test_scenario::return_shared(scenario, price_component_wrapper);
//         };
//     }
// }