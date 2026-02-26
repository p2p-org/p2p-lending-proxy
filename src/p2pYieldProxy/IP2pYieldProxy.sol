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
        address indexed _yieldProtocolAddress, address indexed _asset, uint256 _amount, uint256 _totalDepositedAfter
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
    event P2pYieldProxy__CalledAsAnyFunction(address indexed _yieldProtocolAddress);

    /// @notice Initializes the P2pYieldProxy with the client settings
    /// @param _client The client that will control the proxy
    /// @param _clientBasisPoints The fee share (in basis points) assigned to the client
    function initialize(address _client, uint96 _clientBasisPoints) external;

    /// @notice Deposits assets into a specific ERC4626 vault
    /// @param _vault The ERC4626 vault that receives the deposit
    /// @param _amount The amount of underlying assets to deposit
    function deposit(address _vault, uint256 _amount) external;

    /// @notice Calls an arbitrary allowed function
    /// @param _yieldProtocolAddress The address of the yield protocol
    /// @param _yieldProtocolCalldata The calldata to call the yield protocol
    function callAnyFunction(address _yieldProtocolAddress, bytes calldata _yieldProtocolCalldata) external;

    /// @notice Gets the factory address
    /// @return The factory address
    function getFactory() external view returns (address);

    /// @notice Gets the P2pTreasury address
    /// @return The P2pTreasury address
    function getP2pTreasury() external view returns (address);

    /// @notice Gets the client address
    /// @return The client address
    function getClient() external view returns (address);

    /// @notice Gets the client basis points
    /// @return The client basis points
    function getClientBasisPoints() external view returns (uint96);

    /// @notice Gets the total deposited for an asset
    /// @param _asset The asset address
    /// @return The total deposited
    function getTotalDeposited(address _asset) external view returns (uint256);

    /// @notice Gets the total withdrawn for an asset
    /// @param _asset The asset address
    /// @return The total withdrawn
    function getTotalWithdrawn(address _asset) external view returns (uint256);

    /// @notice Computes the user principal remaining for a given asset
    /// @param _asset The ERC-20 asset address
    /// @return The amount of principal that is still outstanding for the client
    function getUserPrincipal(address _asset) external view returns (uint256);

    /// @notice Calculates accrued rewards for a vault and asset pair
    /// @param _yieldProtocolAddress The address of the yield-bearing vault token
    /// @param _asset The ERC-20 asset backing the vault
    /// @return The signed amount of accrued rewards (positive for profit, negative for loss)
    function calculateAccruedRewards(address _yieldProtocolAddress, address _asset) external view returns (int256);

    /// @notice Returns the timestamp of the last fee collection for an asset
    /// @param _asset The ERC-20 asset address
    /// @return The timestamp of the last fee collection
    function getLastFeeCollectionTime(address _asset) external view returns (uint48);
}
