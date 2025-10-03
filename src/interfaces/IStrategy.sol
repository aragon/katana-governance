// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    /// @notice Handles deposit by creating lock and merging to master token
    /// @param assets Amount of assets to deposit
    function handleDeposit(uint256 assets) external;

    /// @notice Handles deposit of existing token by merging to master token
    /// @param tokenId The token ID to merge
    function handleDepositToken(uint256 tokenId) external;

    /// @notice Handles withdrawal by splitting master token and transferring to receiver
    /// @param receiver The address to receive the split token
    /// @param assets Amount of assets to withdraw
    function handleWithdraw(address receiver, uint256 assets) external returns (uint256);

    /// @notice Returns the total assets managed by the strategy
    /// @return The total amount of assets locked in the master token
    function totalAssets() external view returns (uint256);
}
