// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title IComet
/// @notice Minimal interface for Compound V3 Comet (cUSDCv3, cWETHv3, etc.)
interface IComet {
    event Supply(address indexed from, address indexed dst, uint256 amount);
    event Withdraw(address indexed src, address indexed to, uint256 amount);

    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function balanceOf(address owner) external view returns (uint256);
    function baseToken() external view returns (address);
    function accrueAccount(address account) external;
    function baseTrackingAccrued(address account) external view returns (uint64);
}
