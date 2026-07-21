// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title P2pOperatorCallable
/// @notice Shared operator-gated access control for protocol adapters.
abstract contract P2pOperatorCallable {
    modifier onlyP2pOperator() {
        if (!_isP2pOperator(msg.sender)) {
            _revertNotP2pOperator(msg.sender);
        }
        _;
    }

    function _isP2pOperator(address _caller) internal view returns (bool) {
        return _caller == _getP2pOperator();
    }

    function _getP2pOperator() internal view virtual returns (address);

    function _revertNotP2pOperator(address _caller) internal pure virtual;
}
