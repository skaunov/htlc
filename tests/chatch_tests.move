#[test_only]
/// tests are adapted from <https://github.com/kaleido-io/token-sample-htlc/tree/master/test> and <https://github.com/chatch/hashed-timelock-contract-ethereum/tree/master/test>
/// 
/// I don't think it's a best way to test, and this one should be tested with node RPC instead of from inside the framework; but chance to touch Sui randomness worth it. 
/// Also it's fascinating that it's possible to adapt those (external) tests inside the framework, but that makes it quite boilerplatty in turn.
module htlc::chatch_tests {
    use htlc::htlc::{Self};
    use sui::random::{Self, Random};
    use sui::test_scenario;
    use std::hash;
    use sui::clock::{Self};

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};

    const ADDR_INIT: address = @0xA;
    const ADDR_TARGET: address = @0xB;
    const ADDR_REFUND: address = @0xC;

    // _should fail when no amount is sent_ is covered since even zero balance could be locked
    // _should fail with timelocks in the past_ is covered since it takes duration not timestamp
    // _should reject a duplicate contract request_ is covered since objects allow duplicate locks discreting them by id (though same secret would imply a very tricky, but again it's not realy possible to track this beside good randomness since a lot of locks are even at other chains)

    // should send receiver funds when given the correct secret preimage
    #[test]
    fun test_redeem() {
        // #boilerplate_init: start
        let mut scenario = test_scenario::begin(@0x0);
        // nothing states that `init` `fun` is mandatory
        random::create_for_testing(scenario.ctx());
        let clock_the = clock::create_for_testing(scenario.ctx());
        
        scenario.next_tx(ADDR_INIT);

        let random_the = scenario.take_shared<Random>();
        let secret = 
            random_the.new_generator(scenario.ctx())
                .generate_bytes(32);
        // let clock_the = 
        //     scenario.take_shared<Clock>();
        let hashed = hash::sha2_256(copy secret);

        let coin_the = 
            coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        // #boilerplate_init: end
        
        let coin_id = object::id<Coin<SUI>>(&coin_the);
        htlc::create_lock_object(
            &clock_the, 3_600_000, copy hashed, ADDR_TARGET, ADDR_REFUND, coin_the, 32, scenario.ctx()
        );

        scenario.next_tx(ADDR_TARGET); 
        let lock_the = 
            scenario.take_shared<htlc::LockObject<SUI>>();
        // let lock_id = object::id(&lock_the);
        lock_the.redeem(secret, scenario.ctx());
        
        scenario.next_tx(ADDR_TARGET); 
        let redeemed = 
            scenario.take_from_sender_by_id<Coin<SUI>>(coin_id);
        assert!(redeemed.value() == 10_000_000_000);
        scenario.return_to_sender(redeemed);
        // scenario.take_shared_by_id<LockObject>(lock_id);

        clock_the.destroy_for_testing();
        test_scenario::return_shared(random_the);
        test_scenario::end(scenario);  
    }

    // should fail if preimage does not hash to hashX
    #[test, expected_failure(abort_code = htlc::ESecretPreimageWrong)]
    fun test_redeem_wrongsecret() {
        // #boilerplate_init: start
        let mut scenario = test_scenario::begin(@0x0);
        // nothing states that `init` `fun` is mandatory
        random::create_for_testing(scenario.ctx());
        let clock_the = clock::create_for_testing(scenario.ctx());
        
        scenario.next_tx(ADDR_INIT);

        let mut generator_the = 
            scenario.take_shared<Random>().new_generator(scenario.ctx());
        let secret = generator_the.generate_bytes(32);
        // let clock_the = 
        //     scenario.take_shared<Clock>();
        let hashed = hash::sha2_256(copy secret);

        let coin_the = 
            coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        // #boilerplate_init: end
        
        htlc::create_lock_object(
            &clock_the, 3_600_000, copy hashed, ADDR_TARGET, ADDR_REFUND, coin_the, 32, scenario.ctx()
        );

        scenario.next_tx(ADDR_TARGET); 
        let lock_the = 
            scenario.take_shared<htlc::LockObject<SUI>>();
        // let lock_id = object::id(&lock_the);
        lock_the.redeem(
            generator_the.generate_bytes(32), 
            scenario.ctx()
        );
        abort 1

        // test_scenario::return_shared(clock_the);
        // test_scenario::end(scenario);  
    }

    /* I don't see a rationale for these tests. I feel that with the correct secret it doesn't matter which address sends tx (might be better privacy here), 
    and until the lock is refunded there's no reason to restrict redeem.
    - should fail if caller is not the receiver
    - should fail after timelock expiry */

    // should pass after timelock expiry
    #[test]
    fun test_refund() {
        // #boilerplate_init: start
        let mut scenario = test_scenario::begin(@0x0);
        // nothing states that `init` `fun` is mandatory
        random::create_for_testing(scenario.ctx());
        let mut clock_the = clock::create_for_testing(scenario.ctx());
        
        scenario.next_tx(ADDR_INIT);

        let random_the = scenario.take_shared<Random>();
        let mut generator_the = random_the.new_generator(scenario.ctx());
        let secret = generator_the.generate_bytes(32);
        // let clock_the = 
        //     scenario.take_shared<Clock>();
        let hashed = hash::sha2_256(copy secret);

        let coin_the = 
            coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        // #boilerplate_init: end
        
        let coin_id = object::id<Coin<SUI>>(&coin_the);
        htlc::create_lock_object(
            &clock_the, 3_600_000, copy hashed, ADDR_TARGET, ADDR_REFUND, coin_the, 32, scenario.ctx()
        );

        scenario.next_tx(ADDR_TARGET); 
        clock_the.increment_for_testing(22_000_000);
        
        scenario.next_tx(ADDR_REFUND); 
        let lock_the = 
            scenario.take_shared<htlc::LockObject<SUI>>();
        lock_the.refund(&clock_the, scenario.ctx());
        
        scenario.next_tx(ADDR_REFUND); 
        let refunded = scenario.take_from_sender_by_id<Coin<SUI>>(coin_id);
        assert!(refunded.value() == 10_000_000_000);
        scenario.return_to_sender(refunded);

        clock_the.destroy_for_testing();
        test_scenario::return_shared(random_the);
        test_scenario::end(scenario);  
    }

    // should fail before the timelock expiry
    #[test, expected_failure(abort_code = htlc::ERefundEarly)]
    fun test_refund_early() {
        // #boilerplate_init: start
        let mut scenario = test_scenario::begin(@0x0);
        // nothing states that `init` `fun` is mandatory
        random::create_for_testing(scenario.ctx());
        let clock_the = clock::create_for_testing(scenario.ctx());
        
        scenario.next_tx(ADDR_INIT);

        let mut generator_the = 
            scenario.take_shared<Random>().new_generator(scenario.ctx());
        let secret = generator_the.generate_bytes(32);
        // let clock_the = 
        //     scenario.take_shared<Clock>();
        let hashed = hash::sha2_256(copy secret);

        let coin_the = 
            coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        // #boilerplate_init: end
        
        htlc::create_lock_object(
            &clock_the, 3_600_000, copy hashed, ADDR_TARGET, ADDR_REFUND, coin_the, 32, scenario.ctx()
        );

        scenario.next_tx(ADDR_REFUND); 
        let lock_the = 
            scenario.take_shared<htlc::LockObject<SUI>>();
        lock_the.refund(&clock_the, scenario.ctx());

        abort 4
        // test_scenario::return_shared(clock_the);
        // test_scenario::end(scenario);  
    }

    // _returns empty record when contract doesn't exist_ is handled by Sui object system

    /* _should create new lock and store correct details_ is commented out since it's not trivial only when done via a node RPC and this trivial adaptation requires bloating of the module 
    with `#[test_only]` getters which. Would do that if they had a use outside this test, but since the object is only created and not returned there's no use in that. */
    // #[test]
    // fun test_new() {
    //     // #boilerplate_init: start
    //     let scenario = test_scenario::begin(ADDR_INIT);
    //     // nothing states that `init` `fun` is mandatory
    //     random::create_for_testing(scenario.ctx());
    //     clock::create_for_testing(scenario.ctx());
        
    //     scenario.next_tx(ADDR_INIT);

    //     let secret = 
    //         scenario.take_shared<Random>().new_generator(scenario.ctx())
    //             .generate_bytes(32);
    //     let clock_the = 
    //         scenario.take_shared<Clock>();
    //     let hashed = hash::sha2_256(copy secret);

    //     let coin_the = 
    //         coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
    //     // #boilerplate_init: end
        
    //     htlc::create_lock_object(
    //         &clock_the, 3_600_000, copy hashed, ADDR_TARGET, ADDR_REFUND, coin_the, 32, scenario.ctx()
    //     );

    //     scenario.next_tx(ADDR_INIT);
    //     let lock_the = 
    //         scenario.take_shared<htlc::LockObject<SUI>>();

    //     assert!(&lock_the.refund_adr == &ADDR_REFUND);
    //     assert!(&lock_the.target_adr == &ADDR_TARGET);
    //     assert!(&lock_the.initiator == &ADDR_INIT);
    //     assert!(&lock_the.hashed == &hashed);
    //     assert!(&lock_the.coin == &coin_the);
    //     assert!(&lock_the.hashed == &hashed);
    //     assert!(&lock_the.deadline == 3_600_000);

    //     clock_the.
    //     test_scenario::end(scenario);  
    // }
}
