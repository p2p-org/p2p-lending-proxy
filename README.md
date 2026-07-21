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
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --chain $CHAIN_ID --json --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvvv
```

`Deploy.s.sol` deterministically deploys the shared Superform tooling using CREATE2 so that every network produces the same contract addresses.  
Set the following environment variables (override the defaults only when a network requires different endpoints):

- `PRIVATE_KEY` – broadcaster key (also becomes the default `P2P_SIGNER`)
- `P2P_SIGNER` – optional override for the signer account
- `P2P_OPERATOR` – optional override for the operator account (defaults to `P2P_SIGNER`)
- `SUPERFORM_ROUTER`
- `SUPER_POSITIONS`
- `P2P_TREASURY`
- `REWARDS_DISTRIBUTOR`

This script will:

- deploy and verify on Etherscan the **P2pSuperformProxyFactory**, its reference **P2pSuperformProxy**, the **AllowedCalldataChecker** implementation, proxy, and **ProxyAdmin**
- ensure all CREATE2 salts are reused so the deployed addresses stay identical on Base, Optimism, Mainnet, and any additional chains

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

7. Client-side JS code prepares all the necessary data for the Morpho deposit function. The client's P2pSuperformProxy instance address is fetched from the P2pSuperformProxyFactory contract's `predictP2pYieldProxyAddress` function:

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

8. Client-side JS code checks if the user has already approved the required amount of the deposited token for the P2pSuperformProxy instance. If not, it prompts the user to call the ERC20 `approve` function with an allowance that covers the intended deposit amount.

9. Client-side JS code prompts the user to call the `deposit` function of the P2pSuperformProxyFactory contract:

```solidity
    /// @dev Initiates a deposit through a client specific P2pYieldProxy instance
    /// @param _yieldProtocolCalldata Yield protocol calldata
    /// @param _clientBasisPointsOfDeposit The client basis points (share) of deposit
    /// @param _clientBasisPointsOfProfit The client basis points (share) of profit
    /// @param _p2pSignerSigDeadline The P2pSigner signature deadline
    /// @param _p2pSignerSignature The P2pSigner signature
    /// @return p2pYieldProxyAddress The client's P2pYieldProxy instance address
    function deposit(
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
