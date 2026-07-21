// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Error when the P2pSigner address is zero
error P2pYieldProxyFactory__ZeroP2pSignerAddress();

/// @dev Error when the P2pSigner signature is invalid
error P2pYieldProxyFactory__InvalidP2pSignerSignature();

/// @dev Error when the P2pSigner signature is expired
error P2pYieldProxyFactory__P2pSignerSignatureExpired(uint256 _p2pSignerSigDeadline);

/// @dev Error when reference proxy address is zero
error P2pYieldProxyFactory__ZeroReferenceP2pYieldProxyAddress();

/// @dev Error when reference proxy is not allowlisted
error P2pYieldProxyFactory__ReferenceP2pYieldProxyNotAllowed(address _referenceP2pYieldProxy);

/// @dev Error when reference proxy has already been allowlisted
error P2pYieldProxyFactory__ReferenceP2pYieldProxyAlreadyAllowed(address _referenceP2pYieldProxy);

/// @dev Error when no rules are defined
error P2pYieldProxyFactory__NoRulesDefined(address _target, bytes4 _selector);

/// @dev Error when no calldata is allowed
error P2pYieldProxyFactory__NoCalldataAllowed(address _target, bytes4 _selector);

/// @dev Error when the calldata is too short for the start with rule
error P2pYieldProxyFactory__CalldataTooShortForStartsWithRule(
    uint256 _calldataAfterSelectorLength,
    uint32 _ruleIndex,
    uint32 _bytesCount
);

/// @dev Error when the calldata starts with rule is violated
error P2pYieldProxyFactory__CalldataStartsWithRuleViolated(bytes _actual, bytes _expected);

/// @dev Error when the calldata is too short for the ends with rule
error P2pYieldProxyFactory__CalldataTooShortForEndsWithRule(uint256 _calldataAfterSelectorLength, uint32 _bytesCount);

/// @dev Error when the calldata ends with rule is violated
error P2pYieldProxyFactory__CalldataEndsWithRuleViolated(bytes _actual, bytes _expected);
