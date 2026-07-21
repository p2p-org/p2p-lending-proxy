// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Withdrawable.sol";

abstract contract AccruedRewardsView is Withdrawable {
    function getUserPrincipal(address _asset)
        public
        view
        virtual
        returns (uint256)
    {
        return _getUserPrincipal(_asset);
    }

    function calculateAccruedRewards(address _yieldProtocolAddress, address _asset)
        public
        view
        virtual
        override(Withdrawable)
        returns (int256)
    {
        uint256 currentAmount = _getCurrentAssetAmount(_yieldProtocolAddress, _asset);
        uint256 userPrincipal = _getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function _getCurrentAssetAmount(address _yieldProtocolAddress, address) internal view virtual returns (uint256) {
        return IERC20(_yieldProtocolAddress).balanceOf(address(this));
    }
}
