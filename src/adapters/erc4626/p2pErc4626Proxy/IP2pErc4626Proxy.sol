// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IP2pErc4626Proxy {
    /// @notice Withdraws from an ERC-4626 vault by redeeming shares. Only callable by client.
    /// @param _vault The ERC-4626 vault address.
    /// @param _shares Amount of vault shares to redeem.
    function withdraw(address _vault, uint256 _shares) external;

    /// @notice Withdraws only the accrued yield portion. Only callable by P2P operator.
    /// @param _vault The ERC-4626 vault address.
    function withdrawAccruedRewards(address _vault) external;
}
