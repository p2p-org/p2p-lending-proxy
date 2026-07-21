// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

library Error {
    //////////////////////////////////////////////////////////////
    //                  CONFIGURATION ERRORS                    //
    //////////////////////////////////////////////////////////////
    ///@notice errors thrown in protocol setup

    /// @dev thrown if chain id exceeds max(uint64)
    error BLOCK_CHAIN_ID_OUT_OF_BOUNDS(); // 7ecdf933

    /// @dev thrown if not possible to revoke a role in broadcasting
    error CANNOT_REVOKE_NON_BROADCASTABLE_ROLES(); // c1901a05

    /// @dev thrown if not possible to revoke last admin
    error CANNOT_REVOKE_LAST_ADMIN(); // a567a5a2

    /// @dev thrown if trying to set again pseudo immutables in super registry
    error DISABLED(); // acb78998

    /// @dev thrown if rescue delay is not yet set for a chain
    error DELAY_NOT_SET(); // d0b3066f

    /// @dev thrown if get native token price estimate in paymentHelper is 0
    error INVALID_NATIVE_TOKEN_PRICE(); // 991f334e

    /// @dev thrown if wormhole refund chain id is not set
    error REFUND_CHAIN_ID_NOT_SET(); // 789bb36b

    /// @dev thrown if wormhole relayer is not set
    error RELAYER_NOT_SET(); // e8baf999

    /// @dev thrown if a role to be revoked is not assigned
    error ROLE_NOT_ASSIGNED(); // 35c2f322

    //////////////////////////////////////////////////////////////
    //                  AUTHORIZATION ERRORS                    //
    //////////////////////////////////////////////////////////////
    ///@notice errors thrown if functions cannot be called

    /// COMMON AUTHORIZATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if caller is not address(this), internal call
    error INVALID_INTERNAL_CALL(); // 6566f0ae

    /// @dev thrown if msg.sender is not a valid amb implementation
    error NOT_AMB_IMPLEMENTATION(); // 00e1b7be

    /// @dev thrown if msg.sender is not an allowed broadcaster
    error NOT_ALLOWED_BROADCASTER(); // 5ac755f1

    /// @dev thrown if msg.sender is not broadcast amb implementation
    error NOT_BROADCAST_AMB_IMPLEMENTATION(); // b3af61c9

    /// @dev thrown if msg.sender is not broadcast state registry
    error NOT_BROADCAST_REGISTRY(); // b0acaf9d

    /// @dev thrown if msg.sender is not core state registry
    error NOT_CORE_STATE_REGISTRY(); // 8c1715e2

    /// @dev thrown if msg.sender is not emergency admin
    error NOT_EMERGENCY_ADMIN(); // 445b0c3a

    /// @dev thrown if msg.sender is not emergency queue
    error NOT_EMERGENCY_QUEUE(); // 94949e62

    /// @dev thrown if msg.sender is not minter
    error NOT_MINTER(); // 00914334

    /// @dev thrown if msg.sender is not minter state registry
    error NOT_MINTER_STATE_REGISTRY_ROLE(); // ec1845b2

    /// @dev thrown if msg.sender is not paymaster
    error NOT_PAYMASTER(); // 74891f76

    /// @dev thrown if msg.sender is not payment admin
    error NOT_PAYMENT_ADMIN(); // 62108606

    /// @dev thrown if msg.sender is not protocol admin
    error NOT_PROTOCOL_ADMIN(); // dc855554

    /// @dev thrown if msg.sender is not state registry
    error NOT_STATE_REGISTRY(); // 60e6a64e

    /// @dev thrown if msg.sender is not super registry
    error NOT_SUPER_REGISTRY(); // e7b6503f

    /// @dev thrown if msg.sender is not superform router
    error NOT_SUPERFORM_ROUTER(); // 158a2f6b

    /// @dev thrown if msg.sender is not a superform
    error NOT_SUPERFORM(); // 5279abe6

    /// @dev thrown if msg.sender is not superform factory
    error NOT_SUPERFORM_FACTORY(); // c6ca730c

    /// @dev thrown if msg.sender is not timelock form
    error NOT_TIMELOCK_SUPERFORM(); // 41645ec2

    /// @dev thrown if msg.sender is not timelock state registry
    error NOT_TIMELOCK_STATE_REGISTRY(); // ebe1e902

    /// @dev thrown if msg.sender is not user or disputer
    error NOT_VALID_DISPUTER(); // d8f8c1c0

    /// @dev thrown if the msg.sender is not privileged caller
    error NOT_PRIVILEGED_CALLER(bytes32 role); // c2703cd6

    /// STATE REGISTRY AUTHORIZATION ERRORS
    /// ---------------------------------------------------------

    /// @dev layerzero adapter specific error, thrown if caller not layerzero endpoint
    error CALLER_NOT_ENDPOINT(); // 785db8f2

    /// @dev hyperlane adapter specific error, thrown if caller not hyperlane mailbox
    error CALLER_NOT_MAILBOX(); // b3c9ad31

    /// @dev wormhole relayer specific error, thrown if caller not wormhole relayer
    error CALLER_NOT_RELAYER(); // 5aa1e945

    /// @dev thrown if src chain sender is not valid
    error INVALID_SRC_SENDER(); // 1d527bfc

    //////////////////////////////////////////////////////////////
    //                  INPUT VALIDATION ERRORS                 //
    //////////////////////////////////////////////////////////////
    ///@notice errors thrown if input variables are not valid

    /// COMMON INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if there is an array length mismatch
    error ARRAY_LENGTH_MISMATCH(); // 88adebd2

    /// @dev thrown if payload id does not exist
    error INVALID_PAYLOAD_ID(); // abb45946

    /// @dev error thrown when msg value should be zero in certain payable functions
    error MSG_VALUE_NOT_ZERO(); // 308f275d

    /// @dev thrown if amb ids length is 0
    error ZERO_AMB_ID_LENGTH(); // 308f275d

    /// @dev thrown if address input is address 0
    error ZERO_ADDRESS(); // 538ba4f9

    /// @dev thrown if amount input is 0
    error ZERO_AMOUNT(); // 538ba4f9

    /// @dev thrown if final token is address 0
    error ZERO_FINAL_TOKEN(); // 636b4ef2

    /// @dev thrown if value input is 0
    error ZERO_INPUT_VALUE(); // 021b4ea1

    /// SUPERFORM ROUTER INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if the vaults data is invalid
    error INVALID_SUPERFORMS_DATA(); // 29c0f4af

    /// @dev thrown if receiver address is not set
    error RECEIVER_ADDRESS_NOT_SET(); // abd840db

    /// SUPERFORM FACTORY INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if a form is not ERC165 compatible
    error ERC165_UNSUPPORTED();

    /// @dev thrown if a form is not form interface compatible
    error FORM_INTERFACE_UNSUPPORTED();

    /// @dev error thrown if form implementation address already exists
    error FORM_IMPLEMENTATION_ALREADY_EXISTS();

    /// @dev error thrown if form implementation id already exists
    error FORM_IMPLEMENTATION_ID_ALREADY_EXISTS();

    /// @dev thrown if a form does not exist
    error FORM_DOES_NOT_EXIST();

    /// @dev thrown if form id is larger than max uint16
    error INVALID_FORM_ID();

    /// @dev thrown if superform not on factory
    error SUPERFORM_ID_NONEXISTENT();

    /// @dev thrown if same vault and form implementation is used to create new superform
    error VAULT_FORM_IMPLEMENTATION_COMBINATION_EXISTS();

    /// FORM INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if in case of no txData, if liqData.token != vault.asset()
    /// in case of txData, if token output of swap != vault.asset()
    error DIFFERENT_TOKENS();

    /// @dev thrown if the amount in direct withdraw is not correct
    error DIRECT_WITHDRAW_INVALID_LIQ_REQUEST();

    /// @dev thrown if the amount in xchain withdraw is not correct
    error XCHAIN_WITHDRAW_INVALID_LIQ_REQUEST();

    /// LIQUIDITY BRIDGE INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if route id is blacklisted in socket
    error BLACKLISTED_ROUTE_ID();

    /// @dev thrown if route id is not blacklisted in socket
    error NOT_BLACKLISTED_ROUTE_ID();

    /// @dev error thrown when txData selector of lifi bridge is a blacklisted selector
    error BLACKLISTED_SELECTOR();

    /// @dev error thrown when txData selector of lifi bridge is not a blacklisted selector
    error NOT_BLACKLISTED_SELECTOR();

    /// @dev thrown if a certain action of the user is not allowed given the txData provided
    error INVALID_ACTION();

    /// @dev thrown if in deposits, the liqDstChainId doesn't match the stateReq dstChainId
    error INVALID_DEPOSIT_LIQ_DST_CHAIN_ID();

    /// @dev thrown if index is invalid
    error INVALID_INDEX();

    /// @dev thrown if the chain id in the txdata is invalid
    error INVALID_TXDATA_CHAIN_ID();

    /// @dev thrown if the validation of bridge txData fails due to a destination call present
    error INVALID_TXDATA_NO_DESTINATIONCALL_ALLOWED();

    /// @dev thrown if the validation of bridge txData fails due to wrong receiver
    error INVALID_TXDATA_RECEIVER();

    /// @dev thrown if the validation of bridge txData fails due to wrong token
    error INVALID_TXDATA_TOKEN();

    /// @dev thrown if txData is not present (in case of xChain actions)
    error NO_TXDATA_PRESENT();

    /// STATE REGISTRY INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if payload is being updated with final amounts length different than amounts length
    error DIFFERENT_PAYLOAD_UPDATE_AMOUNTS_LENGTH();

    /// @dev thrown if payload is being updated with tx data length different than liq data length
    error DIFFERENT_PAYLOAD_UPDATE_TX_DATA_LENGTH();

    /// @dev thrown if keeper update final token is different than the vault underlying
    error INVALID_UPDATE_FINAL_TOKEN();

    /// @dev thrown if broadcast finality for wormhole is invalid
    error INVALID_BROADCAST_FINALITY();

    /// @dev thrown if amb id is not valid leading to an address 0 of the implementation
    error INVALID_BRIDGE_ID();

    /// @dev thrown if chain id involved in xchain message is invalid
    error INVALID_CHAIN_ID();

    /// @dev thrown if payload update amount isn't equal to dst swapper amount
    error INVALID_DST_SWAP_AMOUNT();

    /// @dev thrown if message amb and proof amb are the same
    error INVALID_PROOF_BRIDGE_ID();

    /// @dev thrown if order of proof AMBs is incorrect, either duplicated or not incrementing
    error INVALID_PROOF_BRIDGE_IDS();

    /// @dev thrown if rescue data lengths are invalid
    error INVALID_RESCUE_DATA();

    /// @dev thrown if delay is invalid
    error INVALID_TIMELOCK_DELAY();

    /// @dev thrown if amounts being sent in update payload mean a negative slippage
    error NEGATIVE_SLIPPAGE();

    /// @dev thrown if slippage is outside of bounds
    error SLIPPAGE_OUT_OF_BOUNDS();

    /// SUPERPOSITION INPUT VALIDATION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if src senders mismatch in state sync
    error SRC_SENDER_MISMATCH();

    /// @dev thrown if src tx types mismatch in state sync
    error SRC_TX_TYPE_MISMATCH();

    //////////////////////////////////////////////////////////////
    //                  EXECUTION ERRORS                        //
    //////////////////////////////////////////////////////////////
    ///@notice errors thrown due to function execution logic

    /// COMMON EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if the swap in a direct deposit resulted in insufficient tokens
    error DIRECT_DEPOSIT_SWAP_FAILED();

    /// @dev thrown if payload is not unique
    error DUPLICATE_PAYLOAD();

    /// @dev thrown if native tokens fail to be sent to superform contracts
    error FAILED_TO_SEND_NATIVE();

    /// @dev thrown if allowance is not correct to deposit
    error INSUFFICIENT_ALLOWANCE_FOR_DEPOSIT();

    /// @dev thrown if contract has insufficient balance for operations
    error INSUFFICIENT_BALANCE();

    /// @dev thrown if native amount is not at least equal to the amount in the request
    error INSUFFICIENT_NATIVE_AMOUNT();

    /// @dev thrown if payload cannot be decoded
    error INVALID_PAYLOAD();

    /// @dev thrown if payload status is invalid
    error INVALID_PAYLOAD_STATUS();

    /// @dev thrown if payload type is invalid
    error INVALID_PAYLOAD_TYPE();

    /// LIQUIDITY BRIDGE EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if we try to decode the final swap output token in a xChain liquidity bridging action
    error CANNOT_DECODE_FINAL_SWAP_OUTPUT_TOKEN();

    /// @dev thrown if liquidity bridge fails for erc20 or native tokens
    error FAILED_TO_EXECUTE_TXDATA(address token);

    /// @dev thrown if asset being used for deposit mismatches in multivault deposits
    error INVALID_DEPOSIT_TOKEN();

    /// STATE REGISTRY EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if bridge tokens haven't arrived to destination
    error BRIDGE_TOKENS_PENDING();

    /// @dev thrown if withdrawal tx data cannot be updated
    error CANNOT_UPDATE_WITHDRAW_TX_DATA();

    /// @dev thrown if rescue passed dispute deadline
    error DISPUTE_TIME_ELAPSED();

    /// @dev thrown if message failed to reach the specified level of quorum needed
    error INSUFFICIENT_QUORUM();

    /// @dev thrown if broadcast payload is invalid
    error INVALID_BROADCAST_PAYLOAD();

    /// @dev thrown if broadcast fee is invalid
    error INVALID_BROADCAST_FEE();

    /// @dev thrown if retry fees is less than required
    error INVALID_RETRY_FEE();

    /// @dev thrown if broadcast message type is wrong
    error INVALID_MESSAGE_TYPE();

    /// @dev thrown if payload hash is invalid during `retryMessage` on Layezero implementation
    error INVALID_PAYLOAD_HASH();

    /// @dev thrown if update payload function was called on a wrong payload
    error INVALID_PAYLOAD_UPDATE_REQUEST();

    /// @dev thrown if a state registry id is 0
    error INVALID_REGISTRY_ID();

    /// @dev thrown if a form state registry id is 0
    error INVALID_FORM_REGISTRY_ID();

    /// @dev thrown if trying to finalize the payload but the withdraw is still locked
    error LOCKED();

    /// @dev thrown if payload is already updated (during xChain deposits)
    error PAYLOAD_ALREADY_UPDATED();

    /// @dev thrown if payload is already processed
    error PAYLOAD_ALREADY_PROCESSED();

    /// @dev thrown if payload is not in UPDATED state
    error PAYLOAD_NOT_UPDATED();

    /// @dev thrown if rescue is still in timelocked state
    error RESCUE_LOCKED();

    /// @dev thrown if rescue is already proposed
    error RESCUE_ALREADY_PROPOSED();

    /// @dev thrown if payload hash is zero during `retryMessage` on Layezero implementation
    error ZERO_PAYLOAD_HASH();

    /// DST SWAPPER EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if process dst swap is tried for processed payload id
    error DST_SWAP_ALREADY_PROCESSED();

    /// @dev thrown if indices have duplicates
    error DUPLICATE_INDEX();

    /// @dev thrown if failed dst swap is already updated
    error FAILED_DST_SWAP_ALREADY_UPDATED();

    /// @dev thrown if indices are out of bounds
    error INDEX_OUT_OF_BOUNDS();

    /// @dev thrown if failed swap token amount is 0
    error INVALID_DST_SWAPPER_FAILED_SWAP();

    /// @dev thrown if failed swap token amount is not 0 and if token balance is less than amount (non zero)
    error INVALID_DST_SWAPPER_FAILED_SWAP_NO_TOKEN_BALANCE();

    /// @dev thrown if failed swap token amount is not 0 and if native amount is less than amount (non zero)
    error INVALID_DST_SWAPPER_FAILED_SWAP_NO_NATIVE_BALANCE();

    /// @dev forbid xChain deposits with destination swaps without interim token set (for user protection)
    error INVALID_INTERIM_TOKEN();

    /// @dev thrown if dst swap output is less than minimum expected
    error INVALID_SWAP_OUTPUT();

    /// FORM EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if try to forward 4626 share from the superform
    error CANNOT_FORWARD_4646_TOKEN();

    /// @dev thrown in KYCDAO form if no KYC token is present
    error NO_VALID_KYC_TOKEN();

    /// @dev thrown in forms where a certain functionality is not allowed or implemented
    error NOT_IMPLEMENTED();

    /// @dev thrown if form implementation is PAUSED, users cannot perform any action
    error PAUSED();

    /// @dev thrown if shares != deposit output or assets != redeem output when minting SuperPositions
    error VAULT_IMPLEMENTATION_FAILED();

    /// @dev thrown if withdrawal tx data is not updated
    error WITHDRAW_TOKEN_NOT_UPDATED();

    /// @dev thrown if withdrawal tx data is not updated
    error WITHDRAW_TX_DATA_NOT_UPDATED();

    /// @dev thrown when redeeming from vault yields zero collateral
    error WITHDRAW_ZERO_COLLATERAL();

    /// PAYMENT HELPER EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if chainlink is reporting an improper price
    error CHAINLINK_MALFUNCTION();

    /// @dev thrown if chainlink is reporting an incomplete round
    error CHAINLINK_INCOMPLETE_ROUND();

    /// @dev thrown if feed decimals is not 8
    error CHAINLINK_UNSUPPORTED_DECIMAL();

    /// EMERGENCY QUEUE EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if emergency withdraw is not queued
    error EMERGENCY_WITHDRAW_NOT_QUEUED();

    /// @dev thrown if emergency withdraw is already processed
    error EMERGENCY_WITHDRAW_PROCESSED_ALREADY();

    /// SUPERPOSITION EXECUTION ERRORS
    /// ---------------------------------------------------------

    /// @dev thrown if uri cannot be updated
    error DYNAMIC_URI_FROZEN();

    /// @dev thrown if tx history is not found while state sync
    error TX_HISTORY_NOT_FOUND();
}
