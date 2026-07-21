// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../../../p2pYieldProxy/P2pYieldProxy.sol";
import "../IBaseRouter.sol";
import "../IERC1155A.sol";
import "../IRewardsDistributor.sol";
import "../p2pSuperformProxyFactory/IP2pSuperformProxyFactory.sol";
import "./IP2pSuperformProxy.sol";
import {console} from "../../../../lib/forge-std/src/console.sol";

error P2pSuperformProxy__SuperformCalldataTooShort();
error P2pSuperformProxy__SelectorNotSupported(bytes4 _selector);
error P2pSuperformProxy__NativeAmountToDepositAfterFeeLessThanliqRequestNativeAmount(
    uint256 _nativeAmountToDepositAfterFee,
    uint256 _liqRequestNativeAmount
);
error P2pSuperformProxy__LiqRequestTokenShouldBeEqualToPermitForP2pYieldProxyToken(
    address _liqRequestToken,
    address _permitSingleForP2pYieldProxyToken
);
error P2pSuperformProxy__ShouldNotRetain4626();
error P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(
    address _receiverAddress
);
error P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy(
    address _receiverAddressSP
);
error P2pSuperformProxy__AssetShouldNotBeZeroAddress();
error P2pSuperformProxy__NotClaimed(address _token);


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
    receive() external payable {
    }

    /// @inheritdoc IP2pYieldProxy
    function deposit(
        IAllowanceTransfer.PermitSingle calldata _permitSingleForP2pYieldProxy,
        bytes calldata _permit2SignatureForP2pYieldProxy,
        bytes calldata _superformCalldata
    ) external override(P2pYieldProxy, IP2pYieldProxy) payable {
        require (_superformCalldata.length > 4, P2pSuperformProxy__SuperformCalldataTooShort());

        bytes4 selector = bytes4(_superformCalldata[:4]);
        require (
            selector == IBaseRouter.singleDirectSingleVaultDeposit.selector,
            P2pSuperformProxy__SelectorNotSupported(selector)
        );

        SingleDirectSingleVaultStateReq memory req = abi.decode(_superformCalldata[4:], (SingleDirectSingleVaultStateReq));

        uint256 nativeAmountToDepositAfterFee = msg.value * s_clientBasisPointsOfDeposit / 10_000;

        bool isNative = req.superformData.liqRequest.token == NATIVE;
        if (isNative) {
            require (
                nativeAmountToDepositAfterFee >= req.superformData.liqRequest.nativeAmount,
                P2pSuperformProxy__NativeAmountToDepositAfterFeeLessThanliqRequestNativeAmount(
                    nativeAmountToDepositAfterFee,
                    req.superformData.liqRequest.nativeAmount
                )
            );
        } else {
            require (
                req.superformData.liqRequest.token == _permitSingleForP2pYieldProxy.details.token,
                P2pSuperformProxy__LiqRequestTokenShouldBeEqualToPermitForP2pYieldProxyToken(
                    req.superformData.liqRequest.token,
                    _permitSingleForP2pYieldProxy.details.token
                )
            );
            // ETH can still be used to pay for bridging, swaps, etc., so msg.value can be > 0
        }
        require (!req.superformData.retain4626, P2pSuperformProxy__ShouldNotRetain4626());
        require (
            req.superformData.receiverAddress == address(this),
            P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(req.superformData.receiverAddress)
        );
        require (
            req.superformData.receiverAddressSP == address(this),
            P2pSuperformProxy__ReceiverAddressSPShouldBeP2pSuperformProxy(req.superformData.receiverAddressSP)
        );

        _deposit(
            req.superformData.superformId,
            _superformCalldata,
            _permitSingleForP2pYieldProxy,
            _permit2SignatureForP2pYieldProxy,
            false,
            isNative,
            nativeAmountToDepositAfterFee
        );
    }

    /// @inheritdoc IP2pSuperformProxy
    function withdraw(
        bytes calldata _superformCalldata
    ) external {
        require (_superformCalldata.length > 4, P2pSuperformProxy__SuperformCalldataTooShort());
        bytes4 selector = bytes4(_superformCalldata[:4]);

        require (
            selector == IBaseRouter.singleDirectSingleVaultWithdraw.selector,
            P2pSuperformProxy__SelectorNotSupported(selector)
        );

        SingleDirectSingleVaultStateReq memory req = abi.decode(_superformCalldata[4:], (SingleDirectSingleVaultStateReq));

        require (
            req.superformData.receiverAddress == address(this),
            P2pSuperformProxy__ReceiverAddressShouldBeP2pSuperformProxy(req.superformData.receiverAddress)
        );
        require (
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
        require (asset != address(0), P2pSuperformProxy__AssetShouldNotBeZeroAddress());

        IERC1155A(i_superPositions).increaseAllowance(
            i_yieldProtocolAddress,
            req.superformData.superformId,
            req.superformData.amount
        );

        _withdraw(
            req.superformData.superformId,
            asset,
            _superformCalldata
        );
    }

    function batchClaim(
        uint256[] calldata _periodIds,
        address[][] calldata _rewardTokens,
        uint256[][] calldata _amountsClaimed,
        bytes32[][] calldata _proofs
    )
    external
    nonReentrant
    {
        if (msg.sender != s_client) {
            IP2pSuperformProxyFactory(address(i_factory)).checkClaim(
                msg.sender
            );
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
        i_rewardsDistributor.batchClaim(
            address(this),
            _periodIds,
            _rewardTokens,
            _amountsClaimed,
            _proofs
        );

        for (uint256 i = 0; i < uniqueCount; i++) {
            address token = uniqueTokens[i];
            uint256 assetAmountAfter = IERC20(token).balanceOf(address(this));

            uint256 newAssetAmount = assetAmountAfter - assetAmountsBefore[i];
            require (newAssetAmount > 0, P2pSuperformProxy__NotClaimed(token));

            uint256 p2pAmount = (newAssetAmount * (10_000 - s_clientBasisPointsOfProfit)) / 10_000;
            uint256 clientAmount = newAssetAmount - p2pAmount;

            if (p2pAmount > 0) {
                IERC20(token).safeTransfer(i_p2pTreasury, p2pAmount);
            }
            // clientAmount must be > 0 at this point
            IERC20(token).safeTransfer(s_client, clientAmount);

            emit P2pSuperformProxy__Claimed(
                token,
                newAssetAmount,
                p2pAmount,
                clientAmount
            );
        }
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(P2pYieldProxy, IERC165) returns (bool) {
        return interfaceId == type(IP2pSuperformProxy).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
