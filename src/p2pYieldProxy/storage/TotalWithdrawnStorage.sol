// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../structs/P2pStructs.sol";

abstract contract TotalWithdrawnStorage {
    mapping(address => Withdrawn) internal s_totalWithdrawn;

    function getTotalWithdrawn(address _asset)
        public
        view
        virtual
        returns (uint256)
    {
        return s_totalWithdrawn[_asset].amount;
    }

    function getLastFeeCollectionTime(address _asset)
        public
        view
        virtual
        returns (uint48)
    {
        return s_totalWithdrawn[_asset].lastFeeCollectionTime;
    }
}
