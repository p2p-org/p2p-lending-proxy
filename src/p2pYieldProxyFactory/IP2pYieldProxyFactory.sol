// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev External interface of P2pYieldProxyFactory
interface IP2pYieldProxyFactory is IERC165 {
    /// @dev Emitted when the P2pSigner is transferred
    event P2pYieldProxyFactory__P2pSignerTransferred(address indexed _previousP2pSigner, address indexed _newP2pSigner);

    /// @dev Emitted when the deposit is made
    event P2pYieldProxyFactory__Deposited(
        address indexed _client, uint48 indexed _clientBasisPointsOfDeposit, uint48 indexed _clientBasisPointsOfProfit
    );

    /// @dev Emitted when the a new proxy is created
    event P2pYieldProxyFactory__ProxyCreated(
        address _proxy, address _client, uint48 _clientBasisPointsOfDeposit, uint48 _clientBasisPointsOfProfit
    );

    /// @notice Initiates a deposit through a client specific P2pYieldProxy instance
    /// @param _yieldProtocolCalldata Calldata that executes the deposit on the underlying yield protocol
    /// @param _clientBasisPointsOfDeposit Client share of the deposited principal in basis points (max 10_000)
    /// @param _clientBasisPointsOfProfit Client share of the generated profit in basis points (max 10_000)
    /// @param _p2pSignerSigDeadline Expiration timestamp for the P2pSigner signature
    /// @param _p2pSignerSignature Signature issued by the P2pSigner authorising the deposit parameters
    /// @return p2pYieldProxyAddress The address of the client specific P2pYieldProxy used for the deposit
    function deposit(
        bytes calldata _yieldProtocolCalldata,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    ) external payable returns (address p2pYieldProxyAddress);

    /// @notice Computes the deterministic address of a P2pYieldProxy for a client and fee configuration
    /// @param _client Client wallet address
    /// @param _clientBasisPointsOfDeposit Client share of the deposited principal in basis points (max 10_000)
    /// @param _clientBasisPointsOfProfit Client share of the generated profit in basis points (max 10_000)
    /// @return Address of the P2pYieldProxy instance that would be deployed for the provided parameters
    function predictP2pYieldProxyAddress(
        address _client,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit
    ) external view returns (address);

    /// @notice Updates the P2pSigner account that authorises deposits
    /// @param _newP2pSigner Address of the new P2pSigner
    function transferP2pSigner(address _newP2pSigner) external;

    /// @notice Transfers P2pOperator role control to a new account using the two step flow
    /// @param _newP2pOperator Address that will become the new P2pOperator upon acceptance
    function transferP2pOperator(address _newP2pOperator) external;

    /// @notice Finalises a pending two step P2pOperator transfer
    function acceptP2pOperator() external;

    /// @notice Returns the address that is set to become the next P2pOperator
    /// @return pendingP2pOperator Address of the pending P2pOperator
    function getPendingP2pOperator() external view returns (address pendingP2pOperator);

    /// @notice Returns the reference implementation used for cloning new P2pYieldProxy instances
    /// @return Address of the reference P2pYieldProxy implementation
    function getReferenceP2pYieldProxy() external view returns (address);

    /// @notice Computes the message hash that must be signed by the P2pSigner for a deposit authorisation
    /// @param _client Client wallet initiating the deposit
    /// @param _clientBasisPointsOfDeposit Client share of the deposited principal in basis points (max 10_000)
    /// @param _clientBasisPointsOfProfit Client share of the generated profit in basis points (max 10_000)
    /// @param _p2pSignerSigDeadline Expiration timestamp for the signature
    /// @return hash Message hash to be signed by the P2pSigner
    function getHashForP2pSigner(
        address _client,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _p2pSignerSigDeadline
    ) external view returns (bytes32);

    /// @notice Returns the current P2pSigner address authorised to validate deposits
    /// @return Address of the P2pSigner
    function getP2pSigner() external view returns (address);

    /// @notice Returns the current P2pOperator address responsible for administrative actions
    /// @return Address of the P2pOperator
    function getP2pOperator() external view returns (address);

    /// @notice Returns the list of all P2pYieldProxy instances created by the factory
    /// @return Array of deployed P2pYieldProxy addresses
    function getAllProxies() external view returns (address[] memory);
}
