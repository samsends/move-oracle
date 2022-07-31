// Copyright (c) 2022, oracle Protocol
// SPDX-License-Identifier: AGPL-3.0 

/// - anyone can create and share a price_component
/// - the controller of the price_component can reset it to any value
module oracle::price_feed {

    use oracle::price_component;

    use std::vector;
    use sui::transfer;
    use sui::object::{Self, Info};
    use sui::tx_context::{Self, TxContext};

    /// A shared price_component.
    struct PriceFeed has key {
        info: Info,
        controller: address,
        price_components: vector<price_component::PriceComponent>
    }



    public fun price(self: &mut PriceFeed, index: u64): u64 {
        let price_component = vector::borrow(& self.price_components, index);
        price_component::price(price_component)
    }

    /// Create and share a price_component object.
    public entry fun create_price_feed(ctx: &mut TxContext) {
        transfer::share_object(PriceFeed{
            info: object::new(ctx),
            controller: tx_context::sender(ctx),
            price_components: vector::empty(),
        })
    }

    public entry fun add_price_component(self: &mut PriceFeed, controller: address, ctx: &mut TxContext) {
        assert!(self.controller == tx_context::sender(ctx), 0);
        // TODO: update the moving average
        // TODO: create an average price
        // TODO: calculate the confidence across all price components
        vector::push_back(&mut self.price_components, price_component::new(controller))
    }

    public entry fun update_price_component(self: &mut PriceFeed, idx: u64, price: u64, confidence: u64, ctx: &mut TxContext) {
        let price_component = vector::borrow_mut(&mut self.price_components, idx);
        price_component::set(price_component, price, confidence, ctx)
    }
}

#[test_only]
module oracle::price_feed_test {
    use sui::test_scenario;
    use oracle::price_feed;

    #[test]
    fun test_price_feed() {
        let price_feed_admin = @test_1;
        let price_component_admin = @test_2;

        let scenario = &mut test_scenario::begin(&price_feed_admin);

        test_scenario::next_tx(scenario, &price_feed_admin);
        {
            price_feed::create_price_feed(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, &price_feed_admin);
        {
            let price_feed_wrapper = test_scenario::take_shared<price_feed::PriceFeed>(scenario);
            let price_feed = test_scenario::borrow_mut(&mut price_feed_wrapper);

            price_feed::add_price_component(price_feed, price_component_admin, test_scenario::ctx(scenario));
            test_scenario::return_shared(scenario, price_feed_wrapper);
        };

        test_scenario::next_tx(scenario, &price_component_admin);
        {
            let price_feed_wrapper = test_scenario::take_shared<price_feed::PriceFeed>(scenario);
            let price_feed = test_scenario::borrow_mut(&mut price_feed_wrapper);

            price_feed::update_price_component(price_feed, 0, 100, 100, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, price_feed_wrapper);
        };

        test_scenario::next_tx(scenario, &price_feed_admin);
        {
            let price_feed_wrapper = test_scenario::take_shared<price_feed::PriceFeed>(scenario);
            let price_feed = test_scenario::borrow_mut(&mut price_feed_wrapper);

            assert!(price_feed::price(price_feed, 0) == 100, 0);

            test_scenario::return_shared(scenario, price_feed_wrapper);
        }
    }
}