/// Module: htlc
/// HTLC implementation compatible with <https://github.com/decred/atomicswap> hence with many more projects which conform to it. 
/// This enables [Decred Atomic Swaps](https://docs.decred.org/advanced/atomic-swap/) for any `Coin` on Sui 
/// (with addresses not on deny-list) if somebody would want to implement that.
/// 
/// WARNING: It's not possible to check if the hash time locked `Coin` is regulated or its metadata can be altered during the lock-time, 
/// *so it's the duty of the downstream off-chain to check* that the `Coin` isn't regulated, frozen, or if the user takes those 
/// risks participating in the deal. *Note, that's equally important at the audit phase of the protocol.*
/// 
/// During the auditing phase, a lot of things should be checked: starting from correct assets, amounts, and addresses, 
/// to the fact that counterparty code will actually hash to the agreed value, since there's a risk of a situation when correct 
/// hashed value is asserted with a different algorithm/settings which leads to exposure of the _secret_ via "mempool" without 
/// ability to redeem the asset leaving it to be refunded by the counterparty.
/// 
/// # tests
/// After adding some test code it became clear to me that proper tests for this should involve node RPC calls due to the nature of 
/// the protocol. Hence presented tests are somewhat superficial; and still they're divided into two modules: 
/// one adapts test from an Ethereum project and another checks error handling introduced here.

module htlc::htlc {
    use std::hash;
    use sui::coin::Coin;
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::transfer;
    use sui::object::{Self as object, UID, ID};
    use sui::tx_context::{Self as tx_context, TxContext};

    const ESecretPreimageWrong: u64 = 1;
    const ESecretLengthWrong: u64 = 2;
    const ERefund3rdParty: u64 = 3;
    const ERefundEarly: u64 = 4;

    // `Coin` is essential here a) to be able to transfer it to user accounts, and b) to be able to communicate what kind of asset was indeed locked
    // `Balance` won't be inspectable via an RPC in the same way.
    #[allow(lint(coin_field))] 
    /// Representation of the hash time lock itself.
    public struct LockObject<phantom T> has key {
        id: UID,
        /// Timestamp of the instance creation
        created_at: u64,
        /// Timestamp after which `refund` is available
        deadline: u64,
        /// Hashed value of the secret
        hashed: vector<u8>,
        /// Address to which the refunded `Coin` will be sent
        refund_adr: address,
        /// Address to which the redeemed `Coin` will be sent
        target_adr: address,
        /// Address that initiated the lock
        initiator: address,
        /// Byte length of the secret
        secret_length: u8,
        /// Locked `Coin` 
        coin: Coin<T>,
    }

    /// Event emitted when a new lock is created.
    public struct NewLockEvent has copy, drop {
        lock: ID,
        hash: vector<u8>,
        coin: ID,
        refund_adr: address,
        target_adr: address,
        initiator: address,
        deadline: u64,
        duration: u64,
        secret_length: u8,
    }

    /// Event emitted when a lock is redeemed.
    public struct LockClaimedEvent has copy, drop {
        lock: ID,
        secret: vector<u8>,
        claimer: address,
    }

    /// Event emitted when a lock is refunded.
    public struct LockRefundedEvent has copy, drop {
        lock: ID,
        signer: address,
    }

    /// Creates a new hash time lock.
    /// - Parameters:
    ///   - `clock`: Reference to the Clock object to get the current timestamp.
    ///   - `dur`: Duration for which the coin will be locked (in milliseconds).
    ///   - `hashed`: Hashed value of the secret.
    ///   - `target`: Address to which the coin will be transferred upon redemption.
    ///   - `refund`: Address to which the coin will be refunded.
    ///   - `amount`: The coin being locked.
    ///   - `secret_length`: Length of the secret in bytes.
    ///   - `ctx`: Transaction context.
    /// - Emits:
    ///   - `NewLockEvent` with details of the created lock.
    public fun create_lock_object<T>(
        clock: &Clock,
        dur: u64,
        hashed: vector<u8>, 
        target: address, 
        refund: address, 
        amount: Coin<T>,
        secret_length: u8,
        ctx: &mut TxContext
    ) {
        let timestamp = clock::timestamp_ms(clock);
        let lock = LockObject {
            id: object::new(ctx),
            created_at: timestamp, 
            deadline: timestamp + dur,
            hashed, 
            refund_adr: refund,
            target_adr: target,
            initiator: tx_context::sender(ctx),
            coin: amount,
            secret_length,
        };
        
        event::emit(NewLockEvent {
            lock: object::id(&lock),
            hash: lock.hashed,
            coin: object::id(&lock.coin),
            refund_adr: refund,
            target_adr: target,
            initiator: lock.initiator,
            deadline: lock.deadline,
            duration: dur,
            secret_length,
        });
        transfer::share_object(lock);
    }

    /// Creates a new hash time lock with a default duration of 48 hours.
    /// - Parameters:
    ///   - `clock`: Reference to the Clock object to get the current timestamp.
    ///   - `hashed`: Hashed value of the secret.
    ///   - `target`: Address to which the coin will be transferred upon redemption.
    ///   - `refund`: Address to which the coin will be refunded.
    ///   - `amount`: The coin being locked.
    ///   - `secret_length`: Length of the secret in bytes.
    ///   - `ctx`: Transaction context.
    /// - Emits:
    ///   - `NewLockEvent` with details of the created lock.
    public fun create_lock_object_48<T>(
        clock: &Clock,
        hashed: vector<u8>, 
        target: address, 
        refund: address, 
        amount: Coin<T>,
        secret_length: u8,
        ctx: &mut TxContext
    ) {
        create_lock_object(
            clock, 
            172800000, // 48 hours in milliseconds
            hashed, target, refund, amount, secret_length, ctx
        );
    }

    /// Creates a new hash time lock with a default duration of 24 hours.
    /// - Parameters:
    ///   - `clock`: Reference to the Clock object to get the current timestamp.
    ///   - `hashed`: Hashed value of the secret.
    ///   - `target`: Address to which the coin will be transferred upon redemption.
    ///   - `refund`: Address to which the coin will be refunded.
    ///   - `amount`: The coin being locked.
    ///   - `secret_length`: Length of the secret in bytes.
    ///   - `ctx`: Transaction context.
    /// - Emits:
    ///   - `NewLockEvent` with details of the created lock.
    public fun create_lock_object_24<T>(
        clock: &Clock,
        hashed: vector<u8>, 
        target: address, 
        refund: address, 
        amount: Coin<T>,
        secret_length: u8,
        ctx: &mut TxContext
    ) {
        create_lock_object(
            clock, 
            86400000, // 24 hours in milliseconds
            hashed, target, refund, amount, secret_length, ctx
        );
    }

    /// Redeems the lock using the correct secret.
    /// - Parameters:
    ///   - `lock`: The lock object to be redeemed.
    ///   - `secret`: The secret used to redeem the lock.
    ///   - `ctx`: Transaction context.
    /// - Emits:
    ///   - `LockClaimedEvent` with details of the redeemed lock.
    public fun redeem<T>(lock: LockObject<T>, secret: vector<u8>, ctx: &mut TxContext) {
        assert!(lock.secret_length as u64 == secret.length(), ESecretLengthWrong);
        assert!(hash::sha2_256(secret) == lock.hashed, ESecretPreimageWrong);
        
        event::emit(LockClaimedEvent {
            lock: object::id(&lock),
            secret,
            claimer: tx_context::sender(ctx),
        });
        let LockObject { id, coin, target_adr, .. } = lock;
        transfer::public_transfer(coin, target_adr);
        object::delete(id);
    }

    /// Refunds the lock after the deadline has passed.
    /// - Parameters:
    ///   - `lock`: The lock object to be refunded.
    ///   - `clock`: Reference to the Clock object to get the current timestamp.
    ///   - `ctx`: Transaction context.
    /// - Emits:
    ///   - `LockRefundedEvent` with details of the refunded lock.
    public fun refund<T>(lock: LockObject<T>, clock: &Clock, ctx: &mut TxContext) {
        assert!(
            tx_context::sender(ctx) == lock.refund_adr
                || tx_context::sender(ctx) == lock.initiator
                || tx_context::sender(ctx) == lock.target_adr,
            ERefund3rdParty
        );
        assert!(clock::timestamp_ms(clock) > lock.deadline, ERefundEarly);

        event::emit(LockRefundedEvent {
            lock: object::id(&lock),
            signer: tx_context::sender(ctx),
        });
        let LockObject { id, coin, refund_adr, .. } = lock;
        transfer::public_transfer(coin, refund_adr);
        object::delete(id);
    }
}
