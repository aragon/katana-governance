// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IStrategy } from "./IStrategy.sol";

interface IStrategyNFT is IStrategy {
    error MasterTokenAlreadySet();
    error MasterTokenNotSet();

    /// @notice Handles deposit of existing token by merging to master token
    /// @param _tokenId The token ID to merge
    function depositTokenId(uint256 _tokenId) external;

    /// @notice Receives master token id from vault. Must be called
    ///         in the same tx after tokenId is transferred to strategy.
    function receiveMasterToken(uint256 _tokenId) external;
}
