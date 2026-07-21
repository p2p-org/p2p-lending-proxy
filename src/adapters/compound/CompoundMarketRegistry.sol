// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "./@compound/IComet.sol";
import "../../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";

error CompoundMarketRegistry__ZeroAddress();
error CompoundMarketRegistry__AssetNotSupported(address _asset);
error CompoundMarketRegistry__MarketAlreadyRegistered(address _asset);
error CompoundMarketRegistry__BaseTokenMismatch(address _asset, address _baseToken);
error CompoundMarketRegistry__ArrayLengthMismatch();
error CompoundMarketRegistry__EmptyArray();
error CompoundMarketRegistry__NotP2pOperator(address _caller);

contract CompoundMarketRegistry {
    mapping(address asset => address comet) private s_markets;

    IP2pYieldProxyFactory public immutable i_p2pYieldProxyFactory;

    event CompoundMarketRegistry__MarketAdded(address indexed asset, address indexed comet);

    constructor(
        address _factory,
        address[] memory _assets,
        address[] memory _comets
    ) {
        require(_factory != address(0), CompoundMarketRegistry__ZeroAddress());
        require(_assets.length > 0, CompoundMarketRegistry__EmptyArray());
        require(_assets.length == _comets.length, CompoundMarketRegistry__ArrayLengthMismatch());

        i_p2pYieldProxyFactory = IP2pYieldProxyFactory(_factory);

        for (uint256 i; i < _assets.length; ++i) {
            _addMarket(_assets[i], _comets[i]);
        }
    }

    function addMarket(address _asset, address _comet) external {
        address caller = msg.sender;
        require(
            caller == i_p2pYieldProxyFactory.getP2pOperator(),
            CompoundMarketRegistry__NotP2pOperator(caller)
        );
        _addMarket(_asset, _comet);
    }

    function getComet(address _asset) external view returns (address) {
        address comet = s_markets[_asset];
        require(comet != address(0), CompoundMarketRegistry__AssetNotSupported(_asset));
        return comet;
    }

    function _addMarket(address _asset, address _comet) private {
        require(_asset != address(0), CompoundMarketRegistry__ZeroAddress());
        require(_comet != address(0), CompoundMarketRegistry__ZeroAddress());
        require(
            s_markets[_asset] == address(0),
            CompoundMarketRegistry__MarketAlreadyRegistered(_asset)
        );
        require(
            IComet(_comet).baseToken() == _asset,
            CompoundMarketRegistry__BaseTokenMismatch(_asset, IComet(_comet).baseToken())
        );

        s_markets[_asset] = _comet;
        emit CompoundMarketRegistry__MarketAdded(_asset, _comet);
    }
}
