// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "../../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../p2pAaveProxy/P2pAaveProxy.sol";
import "./IP2pAaveProxyFactory.sol";

error P2pAaveProxyFactory__ZeroAavePoolAddress();
error P2pAaveProxyFactory__ZeroAaveDataProviderAddress();

contract P2pAaveProxyFactory is P2pYieldProxyFactory, IP2pAaveProxyFactory {
    address private immutable i_aavePool;
    address private immutable i_aaveDataProvider;

    constructor(
        address _p2pSigner,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _aavePool,
        address _aaveDataProvider
    ) P2pYieldProxyFactory(_p2pSigner) {
        require(_aavePool != address(0), P2pAaveProxyFactory__ZeroAavePoolAddress());
        require(_aaveDataProvider != address(0), P2pAaveProxyFactory__ZeroAaveDataProviderAddress());
        i_aavePool = _aavePool;
        i_aaveDataProvider = _aaveDataProvider;
        i_referenceP2pYieldProxy =
            new P2pAaveProxy(address(this), _p2pTreasury, _allowedCalldataChecker, _aavePool, _aaveDataProvider);
    }

    function getAavePool() external view override returns (address) {
        return i_aavePool;
    }

    function getAaveDataProvider() external view override returns (address) {
        return i_aaveDataProvider;
    }

    function getP2pOperator() public view override(P2pYieldProxyFactory, IP2pYieldProxyFactory) returns (address) {
        return super.getP2pOperator();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxyFactory, IERC165)
        returns (bool)
    {
        return interfaceId == type(IP2pAaveProxyFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
