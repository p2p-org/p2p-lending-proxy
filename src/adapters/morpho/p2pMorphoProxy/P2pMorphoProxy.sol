// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../../../common/IMorphoBundler.sol";
import "../../../common/IDistributor.sol";
import "../../../@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../p2pMorphoProxyFactory/IP2pMorphoProxyFactory.sol";
import "./IP2pMorphoProxy.sol";

error P2pMorphoProxy__NothingClaimed();
error P2pMorphoProxy__InvalidMerklClaimParams();
error P2pMorphoProxy__NotP2pOperator(address _caller);
error P2pMorphoProxy__ZeroAccruedRewards();
error P2pMorphoProxy__ZeroVaultAddress();
error P2pMorphoProxy__VaultAssetNotSet(address _vault);

contract P2pMorphoProxy is P2pYieldProxy, IP2pMorphoProxy {
    using SafeERC20 for IERC20;

    IMorphoBundler private immutable i_morphoBundler;

    modifier onlyP2pOperator() {
        address p2pOperator = i_factory.getP2pOperator();
        require(msg.sender == p2pOperator, P2pMorphoProxy__NotP2pOperator(msg.sender));
        _;
    }

    constructor(
        address _factory,
        address _p2pTreasury,
        address _allowedCalldataChecker,
        address _morphoBundler
    ) P2pYieldProxy(_factory, _p2pTreasury, _allowedCalldataChecker) {
        i_morphoBundler = IMorphoBundler(_morphoBundler);
    }

    /// @inheritdoc IP2pMorphoProxy
    function deposit(address _vault, uint256 _amount) external override(IP2pMorphoProxy, P2pYieldProxy) {
        require(_vault != address(0), P2pMorphoProxy__ZeroVaultAddress());

        address asset = IERC4626(_vault).asset();
        require(asset != address(0), P2pMorphoProxy__VaultAssetNotSet(_vault));

        uint256 minShares = IERC4626(_vault).convertToShares(_amount);
        bytes[] memory dataForMulticall = new bytes[](1);
        dataForMulticall[0] =
            abi.encodeCall(IMorphoBundler.erc4626Deposit, (_vault, _amount, minShares, address(this)));
        bytes memory depositCalldata = abi.encodeCall(IMorphoBundler.multicall, (dataForMulticall));
        _deposit(_vault, address(i_morphoBundler), depositCalldata, asset, _amount, true);
    }

    /// @inheritdoc IP2pMorphoProxy
    function withdraw(address _vault, uint256 _shares) external override onlyClient {
        require(_vault != address(0), P2pMorphoProxy__ZeroVaultAddress());

        address asset = IERC4626(_vault).asset();
        require(asset != address(0), P2pMorphoProxy__VaultAssetNotSet(_vault));

        uint256 minAssets = IERC4626(_vault).convertToAssets(_shares);
        bytes[] memory dataForMulticall = new bytes[](1);
        dataForMulticall[0] = abi.encodeCall(
            IMorphoBundler.erc4626Redeem, (_vault, _shares, minAssets, address(this), address(this))
        );
        bytes memory redeemCalldata = abi.encodeCall(IMorphoBundler.multicall, (dataForMulticall));
        _withdraw(_vault, asset, address(i_morphoBundler), redeemCalldata, _shares);
    }

    /// @inheritdoc IP2pMorphoProxy
    function withdrawAccruedRewards(address _vault) external override onlyP2pOperator {
        require(_vault != address(0), P2pMorphoProxy__ZeroVaultAddress());

        address asset = IERC4626(_vault).asset();
        require(asset != address(0), P2pMorphoProxy__VaultAssetNotSet(_vault));

        int256 amount = calculateAccruedRewards(_vault, asset);
        require(amount > 0, P2pMorphoProxy__ZeroAccruedRewards());

        uint256 shares = IERC4626(_vault).previewWithdraw(uint256(amount));
        bytes[] memory dataForMulticall = new bytes[](1);
        dataForMulticall[0] = abi.encodeCall(
            IMorphoBundler.erc4626Redeem, (_vault, shares, uint256(amount), address(this), address(this))
        );
        bytes memory redeemCalldata = abi.encodeCall(IMorphoBundler.multicall, (dataForMulticall));
        _withdraw(_vault, asset, address(i_morphoBundler), redeemCalldata, shares);
    }

    /// @inheritdoc IP2pMorphoProxy
    function morphoUrdClaim(address _distributor, address _reward, uint256 _amount, bytes32[] calldata _proof)
        external
        override
        nonReentrant
    {
        bool shouldCheckP2pOperator;
        if (msg.sender != s_client) {
            shouldCheckP2pOperator = true;
        }
        IP2pMorphoProxyFactory(address(i_factory)).checkMorphoUrdClaim(
            msg.sender,
            shouldCheckP2pOperator,
            _distributor
        );

        bytes memory urdClaimCalldata =
            abi.encodeCall(IMorphoBundler.urdClaim, (_distributor, address(this), _reward, _amount, _proof, false));
        bytes[] memory dataForMulticall = new bytes[](1);
        dataForMulticall[0] = urdClaimCalldata;

        uint256 assetAmountBefore = IERC20(_reward).balanceOf(address(this));
        i_morphoBundler.multicall(dataForMulticall);
        uint256 assetAmountAfter = IERC20(_reward).balanceOf(address(this));

        uint256 newAssetAmount = assetAmountAfter - assetAmountBefore;
        require(newAssetAmount > 0, P2pMorphoProxy__NothingClaimed());

        uint256 p2pAmount = calculateP2pFeeAmount(newAssetAmount);
        uint256 clientAmount = newAssetAmount - p2pAmount;

        if (p2pAmount > 0) {
            IERC20(_reward).safeTransfer(i_p2pTreasury, p2pAmount);
        }
        IERC20(_reward).safeTransfer(s_client, clientAmount);

        emit P2pMorphoProxy__ClaimedMorphoUrd(
            _distributor,
            _reward,
            newAssetAmount,
            p2pAmount,
            clientAmount
        );
    }

    /// @inheritdoc IP2pMorphoProxy
    function morphoMerklClaim(
        address _distributor,
        address[] calldata _tokens,
        address[] calldata _payoutTokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    )
        external
        override
        nonReentrant
    {
        uint256 claimsLength = _tokens.length;
        if (
            claimsLength == 0 || claimsLength != _amounts.length || claimsLength != _proofs.length
                || (_payoutTokens.length != 0 && _payoutTokens.length != claimsLength)
        ) {
            revert P2pMorphoProxy__InvalidMerklClaimParams();
        }

        bool shouldCheckP2pOperator;
        if (msg.sender != s_client) {
            shouldCheckP2pOperator = true;
        }
        IP2pMorphoProxyFactory(address(i_factory)).checkMorphoUrdClaim(
            msg.sender,
            shouldCheckP2pOperator,
            _distributor
        );

        address thisAddress = address(this);
        address[] memory users = new address[](claimsLength);
        address[] memory payoutTokens = new address[](claimsLength);
        address[] memory uniqueTokens = new address[](claimsLength);
        uint256 uniqueTokensCount;
        for (uint256 i; i < claimsLength; ++i) {
            users[i] = thisAddress;
            address payoutToken = _payoutTokens.length == 0 ? _tokens[i] : _payoutTokens[i];
            if (payoutToken == address(0)) {
                payoutToken = _tokens[i];
            }
            payoutTokens[i] = payoutToken;
            (, bool isNew) = _getTokenIndex(uniqueTokens, uniqueTokensCount, payoutTokens[i]);
            if (isNew) {
                uniqueTokens[uniqueTokensCount] = payoutTokens[i];
                unchecked {
                    ++uniqueTokensCount;
                }
            }
        }

        uint256[] memory balancesBefore = new uint256[](uniqueTokensCount);
        for (uint256 i; i < uniqueTokensCount; ++i) {
            balancesBefore[i] = IERC20(uniqueTokens[i]).balanceOf(thisAddress);
        }

        IDistributor(_distributor).claim(users, _tokens, _amounts, _proofs);

        uint256 totalClaimed;
        for (uint256 i; i < uniqueTokensCount; ++i) {
            address token = uniqueTokens[i];
            uint256 claimedAmount = IERC20(token).balanceOf(thisAddress) - balancesBefore[i];

            if (claimedAmount > 0) {
                totalClaimed += claimedAmount;
                uint256 p2pAmount = calculateP2pFeeAmount(claimedAmount);
                uint256 clientAmount = claimedAmount - p2pAmount;

                if (p2pAmount > 0) {
                    IERC20(token).safeTransfer(i_p2pTreasury, p2pAmount);
                }
                IERC20(token).safeTransfer(s_client, clientAmount);

                emit P2pMorphoProxy__ClaimedMorphoMerkl(
                    _distributor,
                    token,
                    claimedAmount,
                    p2pAmount,
                    clientAmount
                );
            }
        }

        require(totalClaimed > 0, P2pMorphoProxy__NothingClaimed());
    }

    /// @inheritdoc IP2pYieldProxy
    function calculateAccruedRewards(address _vault, address _asset)
        public
        view
        override(IP2pYieldProxy, P2pYieldProxy)
        returns (int256)
    {
        uint256 shares = IERC20(_vault).balanceOf(address(this));
        uint256 currentAmount = IERC4626(_vault).convertToAssets(shares);
        uint256 userPrincipal = getUserPrincipal(_asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy, IERC165)
        returns (bool)
    {
        return interfaceId == type(IP2pMorphoProxy).interfaceId || super.supportsInterface(interfaceId);
    }

    function _getTokenIndex(address[] memory _tokens, uint256 _currentLength, address _token)
        private
        pure
        returns (uint256 index, bool isNew)
    {
        for (uint256 i; i < _currentLength; ++i) {
            if (_tokens[i] == _token) {
                return (i, false);
            }
        }
        return (_currentLength, true);
    }
}
