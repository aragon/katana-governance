// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { VotingEscrow, EscrowIVotesAdapter, GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { AvKATVault } from "./AvKATVault.sol";
import { Executor } from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { VotingEscrowV1_2_0 as Escrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

contract Swapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ActionsFailed();
    error NoBalanceChange();
    error ZeroAddress();
    error LengthMismatch();

    event ClaimAndSwapped(
        address indexed user, address[] tokens, uint256[] claimAmounts, bool useAutoCompound, uint256 compoundAmount
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

    IRewardsDistributor public immutable rewardDistributor;
    address public immutable executor;
    Escrow public immutable escrow;
    address public immutable token;

    constructor(address _rewardDistributor, address _escrow, address _executor) public {
        if (_executor == address(0)) {
            revert ZeroAddress();
        }

        rewardDistributor = IRewardsDistributor(_rewardDistributor);
        executor = _executor;
        escrow = Escrow(_escrow);
        token = escrow.token();
    }

    /// @param _claim Tokens, their respective amounts to claim and merkle proofs for each.
    /// @param _actions The custom actions used to swap tokens in `_outputToken`.
    /// @param _autoCompound How much portion of kat to create lock for. Only applicable if
    ///                     `_autoCompound.useAutoCompound` is set to true.
    /// @return How much amount it created lock with. Only applicable if `_useAutoCompound` is true.
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        AutoCompound calldata _autoCompound
    )
        public
        nonReentrant
        returns (uint256)
    {
        address[] memory users = new address[](_claim.tokens.length);
        for (uint256 i = 0; i < _claim.tokens.length; i++) {
            users[i] = msg.sender;
        }

        // If `_tokens`, `_amounts` and `_proofs` have incorrect size, below reverts.
        // The `user` must have set this contract as a recipient
        // for the `token` prior to calling this.
        // At this point, this contract holds balances on `_tokens`.
        rewardDistributor.claim(users, _claim.tokens, _claim.amounts, _claim.proofs);

        uint256 beforeAmount = IERC20(token).balanceOf(address(this));

        // call actions
        (bool success,) = executor.delegatecall(
            abi.encodeCall(Executor.execute, (bytes32(uint256(uint160(address(this)))), _actions, 0))
        );
        if (!success) {
            revert ActionsFailed();
        }

        uint256 afterAmount = IERC20(token).balanceOf(address(this));

        uint256 diff = afterAmount - beforeAmount;
        if (diff > 0) {
            if (_autoCompound.useAutoCompound) {
                escrow.createLockFor(diff * _autoCompound.weight, msg.sender);
            } else {
                IERC20(token).transfer(msg.sender, diff);
            }
        }

        emit ClaimAndSwapped(msg.sender, _claim.tokens, _claim.amounts, _autoCompound.useAutoCompound, diff);

        return diff;
    }
}
