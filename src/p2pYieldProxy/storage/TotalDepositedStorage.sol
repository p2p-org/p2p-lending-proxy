// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

abstract contract TotalDepositedStorage {
    mapping(address => uint256) internal s_totalDeposited;

    function getTotalDeposited(address _asset)
        public
        view
        virtual
        returns (uint256)
    {
        return s_totalDeposited[_asset];
    }
}
