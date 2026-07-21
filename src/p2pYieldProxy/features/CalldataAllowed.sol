// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../common/AllowedCalldataChecker.sol";
import "../P2pYieldProxyErrors.sol";

abstract contract CalldataAllowed {
    function _allowedCalldataChecker() internal view virtual returns (IAllowedCalldataChecker);

    modifier calldataShouldBeAllowed(
        address _yieldProtocolAddress,
        bytes calldata _yieldProtocolCalldata
    ) {
        bytes4 selector = _getFunctionSelector(_yieldProtocolCalldata);
        _allowedCalldataChecker().checkCalldata(
            _yieldProtocolAddress,
            selector,
            _yieldProtocolCalldata[4:]
        );
        _;
    }

    function _getFunctionSelector(
        bytes calldata _data
    ) private pure returns (bytes4 functionSelector) {
        require(_data.length >= 4, P2pYieldProxy__DataTooShort());
        return bytes4(_data[:4]);
    }
}
