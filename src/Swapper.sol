// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { VotingEscrowV1_2_0 as Escrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Executor } from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { ISwapper } from "src/interfaces/ISwapper.sol";
import { AvKATVault } from "src/AvKATVault.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";

contract Swapper is ISwapper, ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    /// @inheritdoc ISwapper
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        AutoCompound calldata _autoCompound
    )
        public
        nonReentrant
        returns (uint256 diff, uint256 tokenId)
    {
        // If auto compound is enabled, weight must be non zero.
        // If auto compound is disabled, weight must be 0 to avoid ambiguity.
        if (_autoCompound.useAutoCompound != (_autoCompound.weight != 0)) {
            revert InvalidAutoCompoundConfig();
        }

        // make sure weight is never more than 100.
        if (_autoCompound.weight > 100) {
            revert InvalidAutoCompoundWeight();
        }

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

        diff = afterAmount - beforeAmount;
        Locked memory lock;

        // If diff > 0, then kat token balance was increased on this contract.
        // If autoCompound is requested, create a lock with weight percentage.
        // The rest goes to the sender.
        if (diff > 0) {
            uint256 remaining = diff;
            if (_autoCompound.useAutoCompound) {
                lock.amount = (diff * _autoCompound.weight) / 100;
                remaining = diff - lock.amount;

                IERC20(token).approve(address(escrow), lock.amount);
                lock.tokenId = escrow.createLockFor(lock.amount, msg.sender);
            }

            if (remaining > 0) {
                IERC20(token).transfer(msg.sender, remaining);
            }
        }

        emit ClaimAndSwapped(msg.sender, _claim.tokens, _claim.amounts, _autoCompound, lock);

        return (diff, lock.tokenId);
    }
}
