// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../../../p2pYieldProxy/IP2pYieldProxy.sol";

interface IP2pMorphoProxy is IP2pYieldProxy {
    /// @notice Emitted when URD rewards are claimed through the proxy
    event P2pMorphoProxy__ClaimedMorphoUrd(
        address _distributor, address _reward, uint256 _totalAmount, uint256 _p2pAmount, uint256 _clientAmount
    );
    /// @notice Emitted when Merkl rewards are claimed through the proxy
    event P2pMorphoProxy__ClaimedMorphoMerkl(
        address _distributor, address _reward, uint256 _totalAmount, uint256 _p2pAmount, uint256 _clientAmount
    );

    /// @notice Deposits underlying assets into a Morpho ERC4626 vault
    /// @param _vault The ERC4626 vault that should receive the deposit
    /// @param _amount The amount of assets to deposit
    function deposit(address _vault, uint256 _amount) external override;

    /// @notice Withdraws vault shares back to the client
    /// @param _vault The ERC4626 vault from which shares are redeemed
    /// @param _shares The number of vault shares to redeem
    function withdraw(address _vault, uint256 _shares) external;

    /// @notice Withdraws accrued rewards, distributing the fee split to treasury and client
    /// @param _vault The ERC4626 vault whose accrued rewards should be harvested
    function withdrawAccruedRewards(address _vault) external;

    /// @notice Claims URD rewards via the Morpho bundler and distributes the proceeds
    /// @param _distributor The URD distributor contract address
    /// @param _reward The ERC-20 reward token being claimed
    /// @param _amount The amount to claim from the URD program
    /// @param _proof The Merkle proof that validates the claim
    function morphoUrdClaim(address _distributor, address _reward, uint256 _amount, bytes32[] calldata _proof)
        external;

    /// @notice Claims Merkl rewards via the Angle distributor and distributes the proceeds
    /// @param _distributor The Merkl distributor contract address
    /// @param _tokens The ERC-20 reward tokens registered in the Merkle tree
    /// @param _payoutTokens The actual ERC-20 tokens expected to be received (defaults to `_tokens` when zeroed)
    /// @param _amounts The amounts to claim from the Merkl program
    /// @param _proofs The Merkle proofs that validate the claims
    function morphoMerklClaim(
        address _distributor,
        address[] calldata _tokens,
        address[] calldata _payoutTokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external;
}
