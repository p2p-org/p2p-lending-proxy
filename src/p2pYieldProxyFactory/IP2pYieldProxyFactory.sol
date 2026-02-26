// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../common/IAllowedCalldataChecker.sol";

/// @dev External interface of P2pYieldProxyFactory
interface IP2pYieldProxyFactory is IAllowedCalldataChecker, IERC165 {
    /// @dev Emitted when the P2pSigner is transferred
    event P2pYieldProxyFactory__P2pSignerTransferred(address indexed _previousP2pSigner, address indexed _newP2pSigner);

    /// @dev Emitted when the deposit is made
    event P2pYieldProxyFactory__Deposited(address indexed _client, uint96 indexed _clientBasisPoints);

    /// @dev Emitted when the a new proxy is created
    event P2pYieldProxyFactory__ProxyCreated(address _proxy, address _client, uint96 _clientBasisPoints);

    /// @notice Deposits assets for the caller into a specific ERC4626 vault via their proxy
    /// @param _vault The ERC4626 vault that should receive the deposit
    /// @param _amount The amount of assets to deposit
    /// @param _clientBasisPoints The fee share (basis points) that defines the client split
    /// @param _p2pSignerSigDeadline The expiration timestamp for the P2P signer signature
    /// @param _p2pSignerSignature The signature from the P2P signer authorizing the deposit
    /// @return p2pYieldProxyAddress The address of the client-specific yield proxy
    function deposit(
        address _vault,
        uint256 _amount,
        uint96 _clientBasisPoints,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    ) external returns (address p2pYieldProxyAddress);

    /// @notice Predicts the address of the deterministic clone for a client and fee share
    /// @param _client The client address that owns the proxy
    /// @param _clientBasisPoints The fee share (basis points) assigned to the client
    /// @return The predicted proxy address
    function predictP2pYieldProxyAddress(address _client, uint96 _clientBasisPoints) external view returns (address);

    /// @notice Transfers control of the P2P signer to a new address
    /// @param _newP2pSigner The address of the new P2P signer
    function transferP2pSigner(address _newP2pSigner) external;

    /// @notice Returns the implementation used for new proxy clones
    /// @return The reference P2pYieldProxy implementation address
    function getReferenceP2pYieldProxy() external view returns (address);

    /// @notice Computes the P2P signer hash required to authorize a deposit
    /// @param _client The client address that will initiate the deposit
    /// @param _clientBasisPoints The client fee share in basis points
    /// @param _p2pSignerSigDeadline The deadline that limits signature validity
    /// @return The digest that must be signed by the P2P signer
    function getHashForP2pSigner(address _client, uint96 _clientBasisPoints, uint256 _p2pSignerSigDeadline)
        external
        view
        returns (bytes32);

    /// @notice Returns the current P2P signer address
    /// @return The address that may authorize deposits
    function getP2pSigner() external view returns (address);

    /// @notice Returns the address of the active P2P operator
    /// @return The operator address
    function getP2pOperator() external view returns (address);

    /// @notice Returns all proxies that have been created by the factory
    /// @return The list of proxy addresses
    function getAllProxies() external view returns (address[] memory);
}
