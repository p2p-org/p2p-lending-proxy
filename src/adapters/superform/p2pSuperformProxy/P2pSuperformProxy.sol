// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../IBaseForm.sol";
import "../IBaseRouter.sol";
import "../IERC1155A.sol";
import "../IRewardsDistributor.sol";
import "../p2pSuperformProxyFactory/IP2pSuperformProxyFactory.sol";
import "./IP2pSuperformProxy.sol";

error P2pSuperformProxy__SuperformCalldataTooShort();
error P2pSuperformProxy__SelectorNotSupported(bytes4 _selector);
error P2pSuperformProxy__NativeAmountToDepositAfterFeeLessThanliqRequestNativeAmount(
    uint256 _nativeAmountToDepositAfterFee, uint256 _liqRequestNativeAmount
);
error P2pSuperformProxy__ShouldNotRetain4626();
error P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(address _receiverAddress);
error P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy(address _receiverAddressSP);
error P2pSuperformProxy__AssetShouldNotBeZeroAddress();
error P2pSuperformProxy__NotClaimed(address _token);
error P2pSuperformProxy__NoAccruedRewards(uint256 _vaultId, address _asset);
error P2pSuperformProxy__WithdrawAmountExceedsAccrued(uint256 _requestedAssets, uint256 _availableRewards);

contract P2pSuperformProxy is P2pYieldProxy, IP2pSuperformProxy {
    using SafeERC20 for IERC20;

    address internal immutable i_superPositions;
    IRewardsDistributor internal immutable i_rewardsDistributor;

    /// @notice Constructor for P2pEthenaProxy
    /// @param _factory Factory address
    /// @param _p2pTreasury P2pTreasury address
    /// @param _superformRouter SuperformRouter address
    /// @param _superPositions SuperPositions address
    /// @param _allowedCalldataChecker AllowedCalldataChecker
    /// @param _rewardsDistributor RewardsDistributor
    constructor(
        address _factory,
        address _p2pTreasury,
        address _superformRouter,
        address _superPositions,
        address _allowedCalldataChecker,
        address _rewardsDistributor
    ) P2pYieldProxy(_factory, _p2pTreasury, _superformRouter, _allowedCalldataChecker) {
        i_superPositions = _superPositions;
        i_rewardsDistributor = IRewardsDistributor(_rewardsDistributor);
    }

    /// @notice Accept ether from transactions
    receive() external payable {}

    /// @inheritdoc IP2pYieldProxy
    function deposit(bytes calldata _yieldProtocolDepositCalldata)
        external
        payable
        override(P2pYieldProxy, IP2pYieldProxy)
    {
        require(_yieldProtocolDepositCalldata.length > 4, P2pSuperformProxy__SuperformCalldataTooShort());

        bytes4 selector = bytes4(_yieldProtocolDepositCalldata[:4]);
        require(
            selector == IBaseRouter.singleDirectSingleVaultDeposit.selector,
            P2pSuperformProxy__SelectorNotSupported(selector)
        );

        SingleDirectSingleVaultStateReq memory req =
            abi.decode(_yieldProtocolDepositCalldata[4:], (SingleDirectSingleVaultStateReq));

        uint256 nativeAmountToDepositAfterFee = msg.value * s_clientBasisPointsOfDeposit / 10_000;

        address asset;
        if (req.superformData.liqRequest.token == address(0)) {
            address superform = address(uint160(req.superformData.superformId));
            IERC4626 vault = IERC4626(superform);
            asset = vault.asset();
        } else {
            asset = req.superformData.liqRequest.token;
        }

        bool isNative = asset == NATIVE;
        if (isNative) {
            require(
                nativeAmountToDepositAfterFee >= req.superformData.liqRequest.nativeAmount,
                P2pSuperformProxy__NativeAmountToDepositAfterFeeLessThanliqRequestNativeAmount(
                    nativeAmountToDepositAfterFee, req.superformData.liqRequest.nativeAmount
                )
            );
        } else {
            require(asset != address(0), P2pSuperformProxy__AssetShouldNotBeZeroAddress());
            // ETH can still be used to pay for bridging, swaps, etc., so msg.value can be > 0
        }
        require(!req.superformData.retain4626, P2pSuperformProxy__ShouldNotRetain4626());
        require(
            req.superformData.receiverAddress == address(this),
            P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(req.superformData.receiverAddress)
        );
        require(
            req.superformData.receiverAddressSP == address(this),
            P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy(req.superformData.receiverAddressSP)
        );

        uint256 amount = isNative ? 0 : calculateMinAmountToApproveForDeposit(req.superformData.amount);

        _deposit(req.superformData.superformId, asset, amount, _yieldProtocolDepositCalldata, isNative);
    }

    /// @inheritdoc IP2pSuperformProxy
    function withdraw(bytes calldata _superformCalldata) external onlyClient {
        require(_superformCalldata.length > 4, P2pSuperformProxy__SuperformCalldataTooShort());
        bytes4 selector = bytes4(_superformCalldata[:4]);

        require(
            selector == IBaseRouter.singleDirectSingleVaultWithdraw.selector,
            P2pSuperformProxy__SelectorNotSupported(selector)
        );

        SingleDirectSingleVaultStateReq memory req =
            abi.decode(_superformCalldata[4:], (SingleDirectSingleVaultStateReq));

        require(
            req.superformData.receiverAddress == address(this),
            P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(req.superformData.receiverAddress)
        );
        require(
            req.superformData.receiverAddressSP == address(this),
            P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy(req.superformData.receiverAddressSP)
        );

        address asset;
        if (req.superformData.liqRequest.token == address(0)) {
            address superform = address(uint160(req.superformData.superformId));
            IERC4626 vault = IERC4626(superform);
            asset = vault.asset();
        } else {
            asset = req.superformData.liqRequest.token;
        }
        require(asset != address(0), P2pSuperformProxy__AssetShouldNotBeZeroAddress());

        IERC1155A(i_superPositions).increaseAllowance(
            i_yieldProtocolAddress, req.superformData.superformId, req.superformData.amount
        );

        _withdraw(req.superformData.superformId, asset, _superformCalldata);
    }

    /// @inheritdoc IP2pSuperformProxy
    function withdrawAccruedRewards(bytes calldata _superformCalldata) external onlyP2pOperator {
        require(_superformCalldata.length > 4, P2pSuperformProxy__SuperformCalldataTooShort());
        bytes4 selector = bytes4(_superformCalldata[:4]);

        require(
            selector == IBaseRouter.singleDirectSingleVaultWithdraw.selector,
            P2pSuperformProxy__SelectorNotSupported(selector)
        );

        SingleDirectSingleVaultStateReq memory req =
            abi.decode(_superformCalldata[4:], (SingleDirectSingleVaultStateReq));

        require(
            req.superformData.receiverAddress == address(this),
            P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(req.superformData.receiverAddress)
        );
        require(
            req.superformData.receiverAddressSP == address(this),
            P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy(req.superformData.receiverAddressSP)
        );

        address asset;
        if (req.superformData.liqRequest.token == address(0)) {
            address superform = address(uint160(req.superformData.superformId));
            IERC4626 vault = IERC4626(superform);
            asset = vault.asset();
        } else {
            asset = req.superformData.liqRequest.token;
        }
        require(asset != address(0), P2pSuperformProxy__AssetShouldNotBeZeroAddress());

        int256 accruedRewards = calculateAccruedRewards(req.superformData.superformId, asset);
        if (accruedRewards <= 0) {
            revert P2pSuperformProxy__NoAccruedRewards(req.superformData.superformId, asset);
        }

        uint256 accruedRewardsPositive = uint256(accruedRewards);

        uint256 requestedAssets =
            IBaseForm(address(uint160(req.superformData.superformId))).previewRedeemFrom(req.superformData.amount);
        if (requestedAssets > accruedRewardsPositive) {
            revert P2pSuperformProxy__WithdrawAmountExceedsAccrued(requestedAssets, accruedRewardsPositive);
        }

        IERC1155A(i_superPositions).increaseAllowance(
            i_yieldProtocolAddress, req.superformData.superformId, req.superformData.amount
        );

        _withdraw(req.superformData.superformId, asset, _superformCalldata);
    }

    /// @inheritdoc IP2pSuperformProxy
    function batchClaim(
        uint256[] calldata _periodIds,
        address[][] calldata _rewardTokens,
        uint256[][] calldata _amountsClaimed,
        bytes32[][] calldata _proofs
    ) external nonReentrant {
        if (msg.sender != s_client) {
            IP2pSuperformProxyFactory(address(i_factory)).checkClaim(msg.sender);
        }

        // Determine the worst-case total number of token addresses.
        uint256 totalTokens = 0;
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            totalTokens += _rewardTokens[i].length;
        }

        // Allocate a memory array for potential unique tokens.
        address[] memory uniqueTokens = new address[](totalTokens);
        uint256 uniqueCount = 0;

        // Loop through each subarray and each token.
        // For every token, perform a linear search on the uniqueTokens array.
        // If the token is not already present, add it.
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address[] calldata tokenGroup = _rewardTokens[i];
            for (uint256 j = 0; j < tokenGroup.length; j++) {
                address token = tokenGroup[j];
                bool found = false;
                for (uint256 k = 0; k < uniqueCount; k++) {
                    if (uniqueTokens[k] == token) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    uniqueTokens[uniqueCount] = token;
                    uniqueCount++;
                }
            }
        }

        uint256[] memory assetAmountsBefore = new uint256[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            address token = uniqueTokens[i];
            assetAmountsBefore[i] = IERC20(token).balanceOf(address(this));
        }

        // claim _reward token from Superform
        i_rewardsDistributor.batchClaim(address(this), _periodIds, _rewardTokens, _amountsClaimed, _proofs);

        for (uint256 i = 0; i < uniqueCount; i++) {
            address token = uniqueTokens[i];
            uint256 assetAmountAfter = IERC20(token).balanceOf(address(this));

            uint256 newAssetAmount = assetAmountAfter - assetAmountsBefore[i];
            require(newAssetAmount > 0, P2pSuperformProxy__NotClaimed(token));

            uint256 p2pAmount = calculateP2pFeeAmount(newAssetAmount);
            uint256 clientAmount = newAssetAmount - p2pAmount;

            if (p2pAmount > 0) {
                IERC20(token).safeTransfer(i_p2pTreasury, p2pAmount);
            }
            // clientAmount must be > 0 at this point
            IERC20(token).safeTransfer(s_client, clientAmount);

            emit P2pSuperformProxy__Claimed(token, newAssetAmount, p2pAmount, clientAmount);
        }
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }

    /// @inheritdoc IP2pYieldProxy
    function calculateAccruedRewards(uint256 _vaultId, address _asset)
        public
        view
        override(IP2pYieldProxy, P2pYieldProxy)
        returns (int256)
    {
        uint256 shares = IERC1155A(i_superPositions).balanceOf(address(this), _vaultId);
        IBaseForm vault = IBaseForm(address(uint160(_vaultId)));
        uint256 currentAmount = vault.previewRedeemFrom(shares);
        uint256 userPrincipal = getUserPrincipal(_vaultId, _asset);
        return int256(currentAmount) - int256(userPrincipal);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(P2pYieldProxy, IERC165)
        returns (bool)
    {
        return interfaceId == type(IP2pSuperformProxy).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
