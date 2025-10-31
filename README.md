## p2p-yield-proxy

Contracts for depositing and withdrawing ERC-20 tokens from yield protocols.
The current implementation targets the [Ethena](https://docs.ethena.fi/) staking system (USDe / sUSDe).

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

This script deploys the **P2pEthenaProxyFactory** (and its reference **P2pEthenaProxy**) together with a fresh `AllowedCalldataChecker` proxy.

## Basic Ethena flow

See [test/EthenaIntegration.sol](test/EthenaIntegration.sol) for an end-to-end reference executed against a mainnet fork.

### Deposit

1. The backend determines the client basis points and signs the `getHashForP2pSigner` payload using the configured P2P signer:

```solidity
    function getHashForP2pSigner(
        address _client,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline
    ) external view returns (bytes32);
```

2. The client locates (or predicts) its deterministic proxy with `P2pEthenaProxyFactory::predictP2pYieldProxyAddress`.
3. The client approves the proxy for the required USDe allowance using standard `IERC20.approve` (no Permit2 flow).
4. The client calls `P2pEthenaProxyFactory::deposit` providing:

```solidity
    function deposit(
        address _asset,
        uint256 _amount,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    ) external returns (address proxyAddress);
```

The proxy pulls USDe via `transferFrom`, forwards the tokens into `IStakedUSDe.deposit`, and updates the shared accounting tables so future withdrawals can split yield between the client and treasury.

### Withdrawal

The proxy exposes helper flows that mirror Ethena’s queued and instant redemption paths:

- Client-facing helpers mirror Ethena’s queued and instant redemption paths:

```solidity
function cooldownAssets(uint256 assets) external returns (uint256 shares);
function cooldownShares(uint256 shares) external returns (uint256 assets);
function withdrawAfterCooldown() external;
function withdrawWithoutCooldown(uint256 assets) external;
function redeemWithoutCooldown(uint256 shares) external;
```

- Operator-facing helpers consume the current accrued-rewards portion without requiring the client to initiate the flow:

```solidity
function cooldownAssetsAccruedRewards() external returns (uint256 shares);
function withdrawAfterCooldownAccruedRewards() external;
function withdrawWithoutCooldownAccruedRewards() external;
```

- `cooldownAssets`/`cooldownShares` begin the Ethena cooldown and track assets in-flight so `calculateAccruedRewards` remains correct. The operator variant automatically queues the entire accrued balance.
- `withdrawAfterCooldown` finalises an unlock, calling `IStakedUSDe.unstake` and splitting the returned USDe between the client and treasury. The operator variant enforces that the withdrawal does not exceed the accrued rewards.
- `withdrawWithoutCooldown` and `redeemWithoutCooldown` provide the instant Ethena flows when the vault permits them. The operator variant uses the accrued rewards amount directly.

### Arbitrary call escape hatch

`P2pYieldProxy::callAnyFunction` is still available. To keep the surface minimal we deploy an upgradable `AllowedCalldataChecker` that currently reverts everything; operators can upgrade or replace it if a broader API is required. Until rules are relaxed, attempts to call arbitrary functions will revert with `AllowedCalldataChecker__NoAllowedCalldata` as demonstrated in the integration test suite.
