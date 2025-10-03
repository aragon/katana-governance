// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    error OnlyVaultCanCall();

    /// @notice Handles deposit by creating lock and merging to master token
    /// @param _assets Amount of assets to deposit
    function deposit(uint256 _assets) external;

    /// @notice Handles withdrawal by splitting master token and transferring to receiver
    /// @param _receiver The address to receive the split token
    /// @param _assets Amount of assets to withdraw
    function withdraw(address _receiver, uint256 _assets) external returns (uint256);

    /// @notice When vault decides to change strategy, it needs to
    ///         retire old strategy(i.e get masterTokenId back).
    function retireStrategy() external;

    /// @notice Returns the total assets managed by the strategy
    /// @return The total amount of assets locked in the master token
    function totalAssets() external view returns (uint256);
}
