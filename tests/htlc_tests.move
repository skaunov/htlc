#[test_only]
module htlc::htlc_tests {
    use htlc::htlc::{Self};
    use sui::random::{Self, Random};
    use sui::test_scenario;
    use std::hash;
    use sui::clock::{Self};

    use sui::sui::SUI;
    use sui::coin::{Self};

    const ADDR_INIT: address = @0xA;
    const ADDR_TARGET: address = @0xB;
    const ADDR_REFUND: address = @0xC;

    // should fail if preimage does not hash to hashX
    #[test, expected_failure(abort_code = htlc::ESecretLengthWrong)]
    fun test_redeem_wrongsecretlength() {
        // #boilerplate_init: start
        let mut scenario = test_scenario::begin(@0x0);
        // nothing states that `init` `fun` is mandatory
        random::create_for_testing(scenario.ctx());
        let clock_the = clock::create_for_testing(scenario.ctx());
        
        scenario.next_tx(ADDR_INIT);

        let mut generator_the = 
            scenario.take_shared<Random>().new_generator(scenario.ctx());
        let mut secret = generator_the.generate_bytes(32);
        // let clock_the = 
        //     scenario.take_shared<Clock>();
        let hashed = hash::sha2_256(copy secret);

        let coin_the = 
            coin::mint_for_testing<SUI>(10_000_000_000, scenario.ctx());
        // #boilerplate_init: end
        
        htlc::create_lock_object(
            &clock_the, 3_600_000, copy hashed, ADDR_TARGET, 
            ADDR_REFUND, coin_the, 32, scenario.ctx()
        );

        scenario.next_tx(ADDR_TARGET); 
        secret.pop_back();
        // secret.push_back(0);
        let lock_the = 
            scenario.take_shared<htlc::LockObject<SUI>>();
        // let lock_id = object::id(&lock_the);
        lock_the.redeem(
            secret, 
            scenario.ctx()
        );
        abort 2

        // test_scenario::return_shared(clock_the);
        // test_scenario::end(scenario);  
    }

    #[test, expected_failure(abort_code = htlc::ERefund3rdParty)]
    fun test_refund() {
        // #boilerplate_init: start
        let mut scenario = test_scenario::begin(@0x0);
        // nothing states that `init` `fun` is mandatory
        random::create_for_testing(scenario.ctx());
        let mut clock_the = clock::create_for_testing(scenario.ctx());
        
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
        
        // let coin_id = object::id<Coin<SUI>>(&coin_the);
        htlc::create_lock_object(
            &clock_the, 3_600_000, copy hashed, ADDR_TARGET, ADDR_REFUND, coin_the, 32, scenario.ctx()
        );

        scenario.next_tx(ADDR_TARGET); 
        clock_the.increment_for_testing(22_000_000);
        
        scenario.next_tx(@0xF); 
        let lock_the = 
            scenario.take_shared<htlc::LockObject<SUI>>();
        lock_the.refund(&clock_the, scenario.ctx());
        abort 3
        // let refunded = scenario.take_from_sender_by_id<Coin<SUI>>(coin_id);
        // assert!(refunded.value() == 10_000_000_000);

        // test_scenario::return_shared(clock_the);
        // test_scenario::end(scenario);  
    }
}
