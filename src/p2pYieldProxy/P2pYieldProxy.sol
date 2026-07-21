// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import "../@openzeppelin/contracts-upgradable/security/ReentrancyGuardUpgradeable.sol";
import "../@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../@openzeppelin/contracts/utils/Address.sol";
import "../@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "../common/IAllowedCalldataChecker.sol";
import "../p2pYieldProxyFactory/IP2pYieldProxyFactory.sol";
import "../structs/P2pStructs.sol";
import "./IP2pYieldProxy.sol";
import {IERC4626} from "../@openzeppelin/contracts/interfaces/IERC4626.sol";

error P2pYieldProxy__ZeroAddressAsset();
error P2pYieldProxy__ZeroAssetAmount(address _asset);
error P2pYieldProxy__InvalidClientBasisPointsOfDeposit(uint48 _clientBasisPointsOfDeposit);
error P2pYieldProxy__InvalidClientBasisPointsOfProfit(uint48 _clientBasisPointsOfProfit);
error P2pYieldProxy__DifferentActuallyDepositedAmount(address _asset, uint256 _requestedAmount, uint256 _actualAmount);
error P2pYieldProxy__NotFactoryCalled(address _msgSender, IP2pYieldProxyFactory _actualFactory);
error P2pYieldProxy__NotClientCalled(address _msgSender, address _actualClient);
error P2pYieldProxy__ZeroAddressFactory();
error P2pYieldProxy__ZeroAddressP2pTreasury();
error P2pYieldProxy__ZeroAddressYieldProtocolAddress();
error P2pYieldProxy__ZeroAllowedCalldataChecker();
error P2pYieldProxy__DataTooShort();
error P2pYieldProxy__NotP2pOperator(address _msgSender);

/// @title P2pYieldProxy
/// @notice P2pYieldProxy is a contract that allows a client to deposit and withdraw assets from a yield protocol.
abstract contract P2pYieldProxy is Initializable, ReentrancyGuardUpgradeable, ERC165, IP2pYieldProxy {
    using SafeERC20 for IERC20;
    using Address for address;

    address constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev P2pYieldProxyFactory
    IP2pYieldProxyFactory internal immutable i_factory;

    /// @dev P2pTreasury
    address payable internal immutable i_p2pTreasury;

    /// @dev Yield protocol address
    address internal immutable i_yieldProtocolAddress;

    IAllowedCalldataChecker internal immutable i_allowedCalldataChecker;

    /// @dev Client
    address payable internal s_client;

    /// @dev Client basis points of deposit
    uint48 internal s_clientBasisPointsOfDeposit;

    /// @dev Client basis points of profit
    uint48 internal s_clientBasisPointsOfProfit;

    mapping(uint256 vaultId => mapping(address asset => uint256 amount)) internal s_totalDeposited;

    mapping(uint256 vaultId => mapping(address asset => Withdrawn withdrawn)) internal s_totalWithdrawn;

    /// @notice If caller is not factory, revert
    modifier onlyFactory() {
        if (msg.sender != address(i_factory)) {
            revert P2pYieldProxy__NotFactoryCalled(msg.sender, i_factory);
        }
        _;
    }

    /// @notice If caller is not client, revert
    modifier onlyClient() {
        if (msg.sender != s_client) {
            revert P2pYieldProxy__NotClientCalled(msg.sender, s_client);
        }
        _;
    }

    modifier onlyP2pOperator() {
        address p2pOperator = i_factory.getP2pOperator();
        if (msg.sender != p2pOperator) {
            revert P2pYieldProxy__NotP2pOperator(msg.sender);
        }
        _;
    }

    /// @dev Modifier for checking if a calldata is allowed
    /// @param _yieldProtocolAddress The address of the yield protocol
    /// @param _yieldProtocolCalldata The calldata (encoded signature + arguments) to be passed to the yield protocol
    modifier calldataShouldBeAllowed(address _yieldProtocolAddress, bytes calldata _yieldProtocolCalldata) {
        // validate yieldProtocolCalldata for yieldProtocolAddress
        bytes4 selector = _getFunctionSelector(_yieldProtocolCalldata);
        i_allowedCalldataChecker.checkCalldata(_yieldProtocolAddress, selector, _yieldProtocolCalldata[4:]);
        _;
    }

    /// @notice Constructor for P2pYieldProxy
    /// @param _factory The factory address
    /// @param _p2pTreasury The P2pTreasury address
    /// @param _yieldProtocolAddress Yield protocol address
    /// @param _allowedCalldataChecker AllowedCalldataChecker
    constructor(
        address _factory,
        address _p2pTreasury,
        address _yieldProtocolAddress,
        address _allowedCalldataChecker
    ) {
        require(_factory != address(0), P2pYieldProxy__ZeroAddressFactory());
        i_factory = IP2pYieldProxyFactory(_factory);

        require(_p2pTreasury != address(0), P2pYieldProxy__ZeroAddressP2pTreasury());
        i_p2pTreasury = payable(_p2pTreasury);

        require(_yieldProtocolAddress != address(0), P2pYieldProxy__ZeroAddressYieldProtocolAddress());
        i_yieldProtocolAddress = _yieldProtocolAddress;

        require(_allowedCalldataChecker != address(0), P2pYieldProxy__ZeroAllowedCalldataChecker());
        i_allowedCalldataChecker = IAllowedCalldataChecker(_allowedCalldataChecker);
    }

    /// @inheritdoc IP2pYieldProxy
    function initialize(address _client, uint48 _clientBasisPointsOfDeposit, uint48 _clientBasisPointsOfProfit)
        external
        initializer
        onlyFactory
    {
        __ReentrancyGuard_init();

        require(
            _clientBasisPointsOfDeposit <= 10_000,
            P2pYieldProxy__InvalidClientBasisPointsOfDeposit(_clientBasisPointsOfDeposit)
        );
        require(
            _clientBasisPointsOfProfit <= 10_000,
            P2pYieldProxy__InvalidClientBasisPointsOfProfit(_clientBasisPointsOfProfit)
        );

        s_client = payable(_client);
        s_clientBasisPointsOfDeposit = _clientBasisPointsOfDeposit;
        s_clientBasisPointsOfProfit = _clientBasisPointsOfProfit;

        emit P2pYieldProxy__Initialized();
    }

    function deposit(bytes calldata _yieldProtocolDepositCalldata) external payable virtual;

    /// @notice Deposit assets into yield protocol
    /// @param _vaultId vault ID
    /// @param _asset ERC-20 asset address (use NATIVE sentinel for ETH)
    /// @param _amount Amount of ERC-20 asset to transfer from client (ignored for native deposits)
    /// @param _yieldProtocolDepositCalldata calldata for deposit function of yield protocol
    /// @param _isNative whether ETH (native currency) is being deposited
    function _deposit(
        uint256 _vaultId,
        address _asset,
        uint256 _amount,
        bytes memory _yieldProtocolDepositCalldata,
        bool _isNative
    ) internal onlyFactory {
        uint256 nativeAmountToDepositAfterFee = msg.value * s_clientBasisPointsOfDeposit / 10_000;

        if (_isNative) {
            uint256 totalDepositedAfter = s_totalDeposited[_vaultId][NATIVE] + nativeAmountToDepositAfterFee;
            s_totalDeposited[_vaultId][NATIVE] = totalDepositedAfter;
            emit P2pYieldProxy__Deposited(_vaultId, NATIVE, nativeAmountToDepositAfterFee, totalDepositedAfter);
        } else {
            require(_asset != address(0), P2pYieldProxy__ZeroAddressAsset());
            require(_amount > 0, P2pYieldProxy__ZeroAssetAmount(_asset));

            address client = s_client;

            uint256 assetAmountBefore = IERC20(_asset).balanceOf(address(this));

            // Transfer tokens from client to proxy using standard ERC20 transferFrom
            // Client must have approved P2pYieldProxy to spend tokens
            IERC20(_asset).safeTransferFrom(client, address(this), _amount);

            uint256 assetAmountAfter = IERC20(_asset).balanceOf(address(this));
            uint256 actualAmount = assetAmountAfter - assetAmountBefore;

            require(
                actualAmount == _amount, P2pYieldProxy__DifferentActuallyDepositedAmount(_asset, _amount, actualAmount)
            ); // no support for fee-on-transfer or rebasing tokens

            uint256 amountToDepositAfterFee = actualAmount * s_clientBasisPointsOfDeposit / 10_000;

            uint256 totalDepositedAfter = s_totalDeposited[_vaultId][_asset] + amountToDepositAfterFee;
            s_totalDeposited[_vaultId][_asset] = totalDepositedAfter;
            emit P2pYieldProxy__Deposited(_vaultId, _asset, amountToDepositAfterFee, totalDepositedAfter);

            uint256 erc20FeeAmount = actualAmount - amountToDepositAfterFee;
            if (erc20FeeAmount > 0) {
                emit P2pYieldProxy__DepositFee(_asset, erc20FeeAmount);
                IERC20(_asset).safeTransfer(i_p2pTreasury, erc20FeeAmount);
            }

            // Approve yield protocol to spend tokens
            IERC20(_asset).safeIncreaseAllowance(i_yieldProtocolAddress, amountToDepositAfterFee);
        }

        uint256 nativeFeeAmount = msg.value - nativeAmountToDepositAfterFee;
        if (nativeFeeAmount > 0) {
            emit P2pYieldProxy__DepositFee(NATIVE, nativeFeeAmount);
            Address.sendValue(i_p2pTreasury, nativeFeeAmount);
        }

        i_yieldProtocolAddress.functionCallWithValue(_yieldProtocolDepositCalldata, nativeAmountToDepositAfterFee);
    }

    /// @notice Withdraw assets from yield protocol
    /// @param _vaultId vault ID
    /// @param _asset ERC-20 asset address
    /// @param _yieldProtocolWithdrawalCalldata calldata for withdraw function of yield protocol
    function _withdraw(uint256 _vaultId, address _asset, bytes memory _yieldProtocolWithdrawalCalldata)
        internal
        nonReentrant
    {
        int256 accruedRewards = calculateAccruedRewards(_vaultId, _asset);

        bool isNative = _asset == NATIVE;

        uint256 assetAmountBefore = isNative ? address(this).balance : IERC20(_asset).balanceOf(address(this));

        // withdraw assets from Protocol
        i_yieldProtocolAddress.functionCall(_yieldProtocolWithdrawalCalldata);

        uint256 assetAmountAfter = isNative ? address(this).balance : IERC20(_asset).balanceOf(address(this));

        uint256 newAssetAmount = assetAmountAfter - assetAmountBefore;

        if (newAssetAmount == 0) {
            emit P2pYieldProxy__EmergencyWithdrawalQueueFlow(_vaultId, _asset);
            return;
        }

        Withdrawn memory withdrawn = s_totalWithdrawn[_vaultId][_asset];
        uint256 totalWithdrawnBefore = uint256(withdrawn.amount);
        uint256 accruedRewardsPositive;
        if (accruedRewards > 0) {
            accruedRewardsPositive = uint256(accruedRewards);
        }

        uint256 profitPortion = newAssetAmount > accruedRewardsPositive ? accruedRewardsPositive : newAssetAmount;
        uint256 principalPortion = newAssetAmount - profitPortion;

        uint256 totalWithdrawnAfter = totalWithdrawnBefore + principalPortion;

        // update total withdrawn
        withdrawn.amount = uint208(totalWithdrawnAfter);
        withdrawn.lastFeeCollectionTime = uint48(block.timestamp);
        s_totalWithdrawn[_vaultId][_asset] = withdrawn;

        uint256 p2pAmount;
        if (accruedRewards > 0) {
            // That extra 9999 ensures that any nonzero remainder will push the result up by 1 (ceiling division).
            p2pAmount = calculateP2pFeeAmount(profitPortion);
        }
        uint256 clientAmount = newAssetAmount - p2pAmount;

        if (p2pAmount > 0) {
            if (isNative) {
                Address.sendValue(i_p2pTreasury, p2pAmount);
            } else {
                IERC20(_asset).safeTransfer(i_p2pTreasury, p2pAmount);
            }
        }
        // clientAmount must be > 0 at this point
        if (isNative) {
            Address.sendValue(s_client, clientAmount);
        } else {
            IERC20(_asset).safeTransfer(s_client, clientAmount);
        }

        emit P2pYieldProxy__Withdrawn(
            _vaultId, _asset, newAssetAmount, totalWithdrawnAfter, accruedRewards, p2pAmount, clientAmount
        );
    }

    /// @inheritdoc IP2pYieldProxy
    function callAnyFunction(address _yieldProtocolAddress, bytes calldata _yieldProtocolCalldata)
        external
        onlyClient
        nonReentrant
        calldataShouldBeAllowed(_yieldProtocolAddress, _yieldProtocolCalldata)
    {
        emit P2pYieldProxy__CalledAsAnyFunction(_yieldProtocolAddress);
        _yieldProtocolAddress.functionCall(_yieldProtocolCalldata);
    }

    /// @inheritdoc IP2pYieldProxy
    function emergencyTokenWithdraw(address _token) external onlyClient nonReentrant {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        emit P2pYieldProxy__EmergencyWithdrawn(_token, amount);
        IERC20(_token).safeTransfer(s_client, amount);
    }

    /// @inheritdoc IP2pYieldProxy
    function emergencyNativeWithdraw() external onlyClient nonReentrant {
        uint256 amount = address(this).balance;
        emit P2pYieldProxy__EmergencyWithdrawn(NATIVE, amount);
        Address.sendValue(s_client, amount);
    }

    /// @notice Returns function selector (first 4 bytes of data)
    /// @param _data calldata (encoded signature + arguments)
    /// @return functionSelector function selector
    function _getFunctionSelector(bytes calldata _data) private pure returns (bytes4 functionSelector) {
        require(_data.length >= 4, P2pYieldProxy__DataTooShort());
        return bytes4(_data[:4]);
    }

    /// @inheritdoc IP2pYieldProxy
    function getFactory() external view returns (address) {
        return address(i_factory);
    }

    /// @inheritdoc IP2pYieldProxy
    function getP2pTreasury() external view returns (address) {
        return i_p2pTreasury;
    }

    /// @inheritdoc IP2pYieldProxy
    function getYieldProtocolAddress() external view returns (address) {
        return i_yieldProtocolAddress;
    }

    /// @inheritdoc IP2pYieldProxy
    function getAllowedCalldataChecker() external view returns (address) {
        return address(i_allowedCalldataChecker);
    }

    /// @inheritdoc IP2pYieldProxy
    function getClient() external view returns (address) {
        return s_client;
    }

    /// @inheritdoc IP2pYieldProxy
    function getClientBasisPointsOfDeposit() external view returns (uint48) {
        return s_clientBasisPointsOfDeposit;
    }

    /// @inheritdoc IP2pYieldProxy
    function getClientBasisPointsOfProfit() external view returns (uint48) {
        return s_clientBasisPointsOfProfit;
    }

    /// @inheritdoc IP2pYieldProxy
    function getTotalDeposited(uint256 _vaultId, address _asset) external view returns (uint256) {
        return s_totalDeposited[_vaultId][_asset];
    }

    /// @inheritdoc IP2pYieldProxy
    function getTotalWithdrawn(uint256 _vaultId, address _asset) external view returns (uint256) {
        return s_totalWithdrawn[_vaultId][_asset].amount;
    }

    /// @inheritdoc IP2pYieldProxy
    function getUserPrincipal(uint256 _vaultId, address _asset) public view returns (uint256) {
        uint256 totalDeposited = s_totalDeposited[_vaultId][_asset];
        uint256 totalWithdrawn = s_totalWithdrawn[_vaultId][_asset].amount;
        if (totalDeposited > totalWithdrawn) {
            return totalDeposited - totalWithdrawn;
        }
        return 0;
    }

    /// @inheritdoc IP2pYieldProxy
    function calculateAccruedRewards(uint256 _vaultId, address _asset) public view virtual returns (int256);

    /// @inheritdoc IP2pYieldProxy
    function getLastFeeCollectionTime(uint256 _vaultId, address _asset) public view returns (uint48) {
        return s_totalWithdrawn[_vaultId][_asset].lastFeeCollectionTime;
    }

    /// @inheritdoc IP2pYieldProxy
    function calculateMinAmountToApproveForDeposit(uint256 _amountToDeposit) public view returns (uint256) {
        uint48 clientBasisPointsOfDeposit = s_clientBasisPointsOfDeposit;
        if (clientBasisPointsOfDeposit == 0) {
            return _amountToDeposit;
        }
        return (_amountToDeposit * 10_000 + clientBasisPointsOfDeposit - 1) / clientBasisPointsOfDeposit;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IP2pYieldProxy).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Calculates P2P treasury fee amount using ceiling division
    /// @param _amount amount
    /// @return p2pFeeAmount p2p fee amount
    function calculateP2pFeeAmount(uint256 _amount) internal view returns (uint256 p2pFeeAmount) {
        if (_amount == 0) {
            return 0;
        }
        p2pFeeAmount = (_amount * (10_000 - s_clientBasisPointsOfProfit) + 9999) / 10_000;
    }
}
