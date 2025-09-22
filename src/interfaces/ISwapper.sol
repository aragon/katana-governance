// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

interface ISwapper {
    error ActionsFailed();
    error NoBalanceChange();
    error ZeroAddress();
    error LengthMismatch();
    error InvalidAutoCompoundConfig();
    error InvalidAutoCompoundWeight();

    event ClaimAndSwapped(
        address indexed user, address[] tokens, uint256[] claimAmounts, AutoCompound _autoCompound, Locked locked
    );

    struct AutoCompound {
        bool useAutoCompound;
        uint256 weight;
    }

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
    /// @param _autoCompound How much portion of kat to create lock for. Only applicable if
    ///                     `_autoCompound.useAutoCompound` is set to true.
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        AutoCompound calldata _autoCompound
    )
        external
        returns (uint256 diff, uint256 tokenId);
}
