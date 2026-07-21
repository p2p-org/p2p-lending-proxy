// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @dev Minimal interface for Maple PoolPermissionManager (used in tests for whitelisting).
interface IMaplePoolPermissionManager {
    function permissionLevels(address poolManager_) external view returns (uint256);
    function setLenderBitmaps(address[] calldata lenders_, uint256[] calldata bitmaps_) external;
    function setPoolBitmaps(address poolManager_, bytes32[] calldata functionIds_, uint256[] calldata bitmaps_) external;
    function setLenderAllowlist(address poolManager_, address[] calldata lenders_, bool[] calldata statuses_) external;
    function setPoolPermissionLevel(address poolManager_, uint256 permissionLevel_) external;
    function hasPermission(address poolManager_, address lender_, bytes32 functionId_) external view returns (bool);
    function lenderBitmaps(address lender_) external view returns (uint256);
}
