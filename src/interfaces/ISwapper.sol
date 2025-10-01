// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

interface ISwapper {
    error ActionsFailed();
    error NoBalanceChange();
    error ZeroAddress();
    error LengthMismatch();
    error PctTooBig();

    event ClaimAndSwapped(address indexed user, address[] tokens, uint256[] claimAmounts, uint256 pct, Locked locked);

    struct Claim {
        address[] tokens;
        uint256[] amounts;
        bytes32[][] proofs;
    }

    struct Locked {
        uint256 tokenId;
        uint256 amount;
    }

    /// @param _claim Tokens, their respective amounts to claim and merkle proofs for each.
    /// @param _actions The custom actions used to swap tokens in `_outputToken`.
    /// @param _pct How much percentage of swapped kat to create lock for.
    /// @return tokenAmountGained Escrow token received from claims plus any other reward tokens swapped into it.
    /// @return tokenId If `_pct` > 0, `tokenId` is the id of creation lock on escrow, otherwise 0.
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        uint256 _pct
    )
        external
        returns (uint256 tokenAmountGained, uint256 tokenId);
}
