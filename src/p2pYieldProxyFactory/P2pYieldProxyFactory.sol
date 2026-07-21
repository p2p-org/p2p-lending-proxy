// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../@openzeppelin/contracts/proxy/Clones.sol";
import "../@openzeppelin/contracts/utils/Address.sol";
import "../@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "../@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../access/P2pOperator2Step.sol";
import "../p2pYieldProxy/P2pYieldProxy.sol";
import "./IP2pYieldProxyFactory.sol";

/// @dev Error when the P2pSigner address is zero
error P2pYieldProxyFactory__ZeroP2pSignerAddress();

/// @dev Error when the P2pSigner signature is invalid
error P2pYieldProxyFactory__InvalidP2pSignerSignature();

/// @dev Error when the P2pSigner signature is expired
error P2pYieldProxyFactory__P2pSignerSignatureExpired(uint256 _p2pSignerSigDeadline);

/// @title P2pYieldProxyFactory
/// @author P2P Validator <info@p2p.org>
/// @notice P2pYieldProxyFactory is a factory contract for creating P2pYieldProxy contracts
abstract contract P2pYieldProxyFactory is P2pOperator2Step, ERC165, IP2pYieldProxyFactory {
    using SignatureChecker for address;
    using ECDSA for bytes32;

    /// @notice Reference P2pYieldProxy contract
    P2pYieldProxy internal immutable i_referenceP2pYieldProxy;

    /// @notice P2pSigner address
    address internal s_p2pSigner;

    /// @notice All proxies
    address[] internal s_allProxies;

    /// @notice Modifier to check if the P2pSigner signature should not expire
    modifier p2pSignerSignatureShouldNotExpire(uint256 _p2pSignerSigDeadline) {
        require(
            block.timestamp <= _p2pSignerSigDeadline,
            P2pYieldProxyFactory__P2pSignerSignatureExpired(_p2pSignerSigDeadline)
        );
        _;
    }

    /// @notice Modifier to check if the P2pSigner signature should be valid
    modifier p2pSignerSignatureShouldBeValid(
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    ) {
        require(
            s_p2pSigner.isValidSignatureNow(
                getHashForP2pSigner(
                    msg.sender, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit, _p2pSignerSigDeadline
                ).toEthSignedMessageHash(),
                _p2pSignerSignature
            ),
            P2pYieldProxyFactory__InvalidP2pSignerSignature()
        );
        _;
    }

    /// @notice Constructor for P2pYieldProxyFactory
    /// @param _p2pSigner The P2pSigner address
    /// @param _p2pOperator The P2pOperator address
    constructor(address _p2pSigner, address _p2pOperator) P2pOperator(_p2pOperator) {
        _transferP2pSigner(_p2pSigner);
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function transferP2pSigner(address _newP2pSigner) external onlyP2pOperator {
        _transferP2pSigner(_newP2pSigner);
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function transferP2pOperator(address _newP2pOperator)
        public
        virtual
        override(P2pOperator2Step, IP2pYieldProxyFactory)
    {
        P2pOperator2Step.transferP2pOperator(_newP2pOperator);
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function acceptP2pOperator() public virtual override(P2pOperator2Step, IP2pYieldProxyFactory) {
        P2pOperator2Step.acceptP2pOperator();
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getPendingP2pOperator()
        public
        view
        virtual
        override(P2pOperator2Step, IP2pYieldProxyFactory)
        returns (address)
    {
        return P2pOperator2Step.getPendingP2pOperator();
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function deposit(
        bytes calldata _yieldProtocolCalldata,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _p2pSignerSigDeadline,
        bytes calldata _p2pSignerSignature
    )
        external
        payable
        p2pSignerSignatureShouldNotExpire(_p2pSignerSigDeadline)
        p2pSignerSignatureShouldBeValid(
            _clientBasisPointsOfDeposit,
            _clientBasisPointsOfProfit,
            _p2pSignerSigDeadline,
            _p2pSignerSignature
        )
        returns (address p2pYieldProxyAddress)
    {
        // create proxy if not created yet
        P2pYieldProxy p2pYieldProxy = _getOrCreateP2pYieldProxy(_clientBasisPointsOfDeposit, _clientBasisPointsOfProfit);

        // deposit via proxy
        p2pYieldProxy.deposit{value: msg.value}(_yieldProtocolCalldata);

        emit P2pYieldProxyFactory__Deposited(msg.sender, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit);

        p2pYieldProxyAddress = address(p2pYieldProxy);
    }

    function _transferP2pSigner(address _newP2pSigner) private {
        require(_newP2pSigner != address(0), P2pYieldProxyFactory__ZeroP2pSignerAddress());
        emit P2pYieldProxyFactory__P2pSignerTransferred(s_p2pSigner, _newP2pSigner);
        s_p2pSigner = _newP2pSigner;
    }

    /// @notice Creates a new P2pYieldProxy contract instance if not created yet
    function _getOrCreateP2pYieldProxy(uint48 _clientBasisPointsOfDeposit, uint48 _clientBasisPointsOfProfit)
        private
        returns (P2pYieldProxy p2pYieldProxy)
    {
        address p2pYieldProxyAddress =
            predictP2pYieldProxyAddress(msg.sender, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit);
        uint256 codeSize = p2pYieldProxyAddress.code.length;
        if (codeSize > 0) {
            return P2pYieldProxy(p2pYieldProxyAddress);
        }

        p2pYieldProxy = P2pYieldProxy(
            Clones.cloneDeterministic(
                address(i_referenceP2pYieldProxy),
                _getSalt(msg.sender, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit)
            )
        );

        p2pYieldProxy.initialize(msg.sender, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit);

        s_allProxies.push(address(p2pYieldProxy));

        emit P2pYieldProxyFactory__ProxyCreated(
            address(p2pYieldProxy), msg.sender, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit
        );
    }

    /// @notice Calculates the salt required for deterministic clone creation
    /// depending on client address and client basis points
    /// @param _clientAddress address
    /// @param _clientBasisPointsOfDeposit The client basis points (10000 = 100%) of deposit
    /// @param _clientBasisPointsOfProfit The client basis points (10000 = 100%) of profit
    /// @return bytes32 salt
    function _getSalt(address _clientAddress, uint48 _clientBasisPointsOfDeposit, uint48 _clientBasisPointsOfProfit)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_clientAddress, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit));
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function predictP2pYieldProxyAddress(
        address _client,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit
    ) public view returns (address) {
        return Clones.predictDeterministicAddress(
            address(i_referenceP2pYieldProxy),
            _getSalt(_client, _clientBasisPointsOfDeposit, _clientBasisPointsOfProfit)
        );
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getReferenceP2pYieldProxy() external view returns (address) {
        return address(i_referenceP2pYieldProxy);
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getP2pOperator() public view virtual override(IP2pYieldProxyFactory, P2pOperator) returns (address) {
        return P2pOperator.getP2pOperator();
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getHashForP2pSigner(
        address _client,
        uint48 _clientBasisPointsOfDeposit,
        uint48 _clientBasisPointsOfProfit,
        uint256 _p2pSignerSigDeadline
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _client,
                _clientBasisPointsOfDeposit,
                _clientBasisPointsOfProfit,
                _p2pSignerSigDeadline,
                address(this),
                block.chainid
            )
        );
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getP2pSigner() external view returns (address) {
        return s_p2pSigner;
    }

    /// @inheritdoc IP2pYieldProxyFactory
    function getAllProxies() external view returns (address[] memory) {
        return s_allProxies;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IP2pYieldProxyFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
