## p2p-yield-proxy

Contracts for depositing and withdrawing ERC-20 tokens from yield protocols.
The current implementation is only compatible with [Superform](https://www.superform.xyz/) protocol. 

## Running tests

```shell
curl -L https://foundry.paradigm.xyz | bash
source /Users/$USER/.bashrc
foundryup
forge test
```

## Deployment

```shell
forge script script/DeployBase.s.sol:Deploy --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --chain $CHAIN_ID --json --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvvv
```

This script will:

- deploy and verify on Etherscan the **P2pSuperformProxyFactory** and **P2pSuperformProxy** contracts
- set the **P2pTreasury** address permanently in the P2pSuperformProxyFactory
- set the rules for Superform specific deposit and withdrawal functions

## Basic use case

![Basic use case diagram](image-1.png)

#### Superform Deposit flow

Look at [function _doDeposit()](test/OptimismUSDT.t.sol#L430) for a reference implementation of the flow.

1. Website User (called Client in contracts) calls Backend with its (User's) Ethereum address and some Merchant info.

2. Backend uses Merchant info to determine the P2P fee (expressed as client basis points in the contracts).

3. Backend calls P2pSuperformProxyFactory's `getHashForP2pSigner` function to get the hash for the P2pSigner.

```solidity
    /// @dev Gets the hash for the P2pSigner
    /// @param _client The address of client
    /// @param _clientBasisPoints The client basis points
    /// @param _p2pSignerSigDeadline The P2pSigner signature deadline
    /// @return The hash for the P2pSigner
    function getHashForP2pSigner(
        address _client,
        uint48 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline
    ) external view returns (bytes32);
```

4. Backend signs the hash with the P2pSigner's private key using `eth_sign`. Signing is necessary to authenticate the client basis points in the contracts.

5. Backend calls Superform API to generate Superform deposit calldata.

6. Backend returns JSON to the User with (client address, client basis points, signature deadline, and the signature).

7. Client-side JS code prepares all the necessary data for the Morpho deposit function. Since the deposited tokens will first go from the client to the client's P2pSuperformProxy instance and then from the P2pSuperformProxy instance into the Superform protocol, both of these transfers are approved by the client via Permit2. The client's P2pSuperformProxy instance address is fetched from the P2pSuperformProxyFactory contract's `predictP2pYieldProxyAddress` function:

```solidity
    /// @dev Computes the address of a P2pYieldProxy created by `_getOrCreateP2pYieldProxy` function
    /// @dev P2pYieldProxy instances are guaranteed to have the same address if _feeDistributorInstance is the same
    /// @param _client The address of client
    /// @param _clientBasisPointsOfDeposit The client basis points (share) of deposit
    /// @param _clientBasisPointsOfProfit The client basis points (share) of profit
    /// @return address The address of the P2pYieldProxy instance
    function predictP2pYieldProxyAddress(
        address _client,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit
    ) external view returns (address);
```

8. Client-side JS code checks if User has already approved the required amount of the deposited token for Permit2. If not, it prompts the User to call the `approve` function of the deposited token contract with the uint256 MAX value and Permit2 contract as the spender.

9. Client-side JS code prompts the User to do `eth_signTypedData_v4` to sign `PermitSingle` from the User's wallet into the P2pSuperformProxy instance

10. Client-side JS code prompts the User to call the `deposit` function of the P2pSuperformProxyFactory contract:

```solidity
    /// @dev Deposits the yield protocol
    /// @param _permitSingleForP2pYieldProxy The permit single for P2pYieldProxy
    /// @param _permit2SignatureForP2pYieldProxy The permit2 signature for P2pYieldProxy
    /// @param _yieldProtocolCalldata Yield protocol calldata
    /// @param _clientBasisPointsOfDeposit The client basis points (share) of deposit
    /// @param _clientBasisPointsOfProfit The client basis points (share) of profit
    /// @param _p2pSignerSigDeadline The P2pSigner signature deadline
    /// @param _p2pSignerSignature The P2pSigner signature
    /// @return p2pYieldProxyAddress The client's P2pYieldProxy instance address
    function deposit(
        IAllowanceTransfer.PermitSingle memory _permitSingleForP2pYieldProxy,
        bytes calldata _permit2SignatureForP2pYieldProxy,
        bytes calldata _yieldProtocolCalldata,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    )
    external
    payable
    returns (address p2pYieldProxyAddress);
```

#### Superform Withdrawal flow

Look at [function _doWithdraw()](test/OptimismUSDT.t.sol#L486) for a reference implementation of the flow.

1. Website User calls P2P.org's backend for Superform withdrawal calldata.

2. P2P.org's backend calls Superform API for Superform withdrawal calldata.

3. P2P.org's backend returns Superform withdrawal calldata to the User.

4. Client-side JS code prepares all the necessary data for the Superform `singleDirectSingleVaultWithdraw` function.

5. Client-side JS code prompts the User to call the `withdraw` function of the client's instance of the P2pSuperformProxy contract:

```solidity
    /// @notice Withdraw assets from Superform protocol
    /// @param _superformCalldata calldata for withdraw function of Superform protocol
    function withdraw(
        bytes calldata _superformCalldata
    ) external;
```

The P2pSuperformProxy contract will redeem the tokens from Superform and send them to User. The amount on top of the deposited amount is split between the User and the P2pTreasury according to the client basis points.


## Calling any function on any contracts via P2pSuperformProxy

It's possible for the User to call any function on any contracts via P2pSuperformProxy. This can be useful if it appears that functions of yield protocols beyond simple deposit and withdrawal are needed. Also, it can be useful for claiming any airdrops unknown in advance.

Before the User can use this feature, the P2P operator needs to deploy a new contract implementing the `IAllowedCalldataChecker` interface and then the function `upgrade` function on ProxyAdmin:

```solidity
    MockAllowedCalldataChecker newImplementation = new MockAllowedCalldataChecker();
    admin.upgrade(ITransparentUpgradeableProxy(address(tup)), address(newImplementation));
```

The rules should be as strict as possible to prevent any undesired function calls.

Once the rules are set, the User can call the permitted function on the permitted contract with the permitted calldata via P2pSuperformProxy's `callAnyFunction` function:

```solidity
    /// @notice Calls an arbitrary allowed function
    /// @param _yieldProtocolAddress The address of the yield protocol
    /// @param _yieldProtocolCalldata The calldata to call the yield protocol
    function callAnyFunction(
        address _yieldProtocolAddress,
        bytes calldata _yieldProtocolCalldata
    )
    external;
```
