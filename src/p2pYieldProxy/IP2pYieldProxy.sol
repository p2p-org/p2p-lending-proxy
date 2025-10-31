// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev External interface of P2pYieldProxy declared to support ERC165 detection.
interface IP2pYieldProxy is IERC165 {

    /// @notice Emitted when the P2pYieldProxy is initialized
    event P2pYieldProxy__Initialized();

    /// @notice Emitted when a deposit is made
    event P2pYieldProxy__Deposited(
        address indexed _yieldProtocolAddress,
        address indexed _asset,
        uint256 _amount,
        uint256 _totalDepositedAfter
    );

    /// @notice Emitted when a withdrawal is made
    event P2pYieldProxy__Withdrawn(
        address indexed _yieldProtocolAddress,
        address indexed _vault,
        address indexed _asset,
        uint256 _assets,
        uint256 _totalWithdrawnAfter,
        int256 _accruedRewards,
        uint256 _p2pAmount,
        uint256 _clientAmount
    );

    /// @notice Emitted when an arbitrary allowed function is called
    event P2pYieldProxy__CalledAsAnyFunction(
        address indexed _yieldProtocolAddress
    );

    /// @notice Initializes the proxy with its client and revenue split configuration.
    /// @param _client Address of the client that will control the proxy.
    /// @param _clientBasisPoints Portion of accrued rewards (in basis points) assigned to the client.
    function initialize(
        address _client,
        uint96 _clientBasisPoints
    )
    external;

    /// @notice Deposits the given asset amount into the underlying yield protocol.
    /// @param _asset Address of the ERC-20 asset the client wants to supply.
    /// @param _amount Amount of `_asset` in wei requested for deposit.
    function deposit(address _asset, uint256 _amount) external;

    /// @notice Calls an arbitrary function on the underlying protocol when allowed by the checker.
    /// @param _yieldProtocolAddress Address of the downstream protocol to call.
    /// @param _yieldProtocolCalldata Calldata payload forwarded to the downstream protocol.
    function callAnyFunction(
        address _yieldProtocolAddress,
        bytes calldata _yieldProtocolCalldata
    )
    external;

    /// @notice Returns the factory that deployed and controls the proxy lifecycle.
    /// @return factory Address of the factory contract.
    function getFactory() external view returns (address);

    /// @notice Returns the treasury address receiving the protocol share of accrued rewards.
    /// @return treasury Address of the P2P treasury.
    function getP2pTreasury() external view returns (address);

    /// @notice Returns the client that is authorised to operate the proxy.
    /// @return client Address of the client.
    function getClient() external view returns (address);

    /// @notice Returns the share of accrued rewards reserved for the client.
    /// @return clientBasisPoints Portion of rewards expressed in basis points.
    function getClientBasisPoints() external view returns (uint96);

    /// @notice Returns the cumulative amount of an asset deposited through the proxy.
    /// @param _asset Address of the asset to query.
    /// @return totalDeposited Total amount ever deposited for the asset.
    function getTotalDeposited(address _asset) external view returns (uint256);

    /// @notice Returns the cumulative amount of an asset withdrawn through the proxy.
    /// @param _asset Address of the asset to query.
    /// @return totalWithdrawn Total amount ever withdrawn for the asset.
    function getTotalWithdrawn(address _asset) external view returns (uint256);

    /// @notice Returns the principal still attributable to the client for a given asset.
    /// @param _asset Address of the asset to query.
    /// @return principal Client principal currently tracked for the asset.
    function getUserPrincipal(address _asset) external view returns (uint256 principal);

    /// @notice Computes the accrued rewards for a given protocol/asset pair.
    /// @param _yieldProtocolAddress Address of the yield protocol used for balance lookups.
    /// @param _asset Address of the asset that was deposited.
    /// @return accruedRewards Signed difference between the current balance and the tracked principal.
    function calculateAccruedRewards(
        address _yieldProtocolAddress,
        address _asset
    ) external view returns (int256 accruedRewards);

    /// @notice Returns the timestamp when performance fees were last collected for an asset.
    /// @param _asset Address of the asset to query.
    /// @return lastFeeCollectionTime Timestamp of the latest fee collection.
    function getLastFeeCollectionTime(address _asset)
        external
        view
        returns (uint48 lastFeeCollectionTime);
}
