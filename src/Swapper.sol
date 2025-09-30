// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { VotingEscrowV1_2_0 as Escrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

import { IExecutor } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { ISwapper } from "src/interfaces/ISwapper.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";

contract Swapper is ISwapper, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The address of the rewards distributor where swapper can claim tokens.
    IRewardsDistributor public immutable rewardDistributor;

    /// @notice The executor contract Swapper delegates the actions execution to.
    address public immutable executor;

    /// @notice The escrow contract address
    Escrow public immutable escrow;

    /// @notice The ERC20 token address escrow uses
    IERC20 public immutable token;

    constructor(address _rewardDistributor, address _escrow, address _executor) {
        if (_executor == address(0)) {
            revert ZeroAddress();
        }

        rewardDistributor = IRewardsDistributor(_rewardDistributor);
        executor = _executor;
        escrow = Escrow(_escrow);
        token = IERC20(escrow.token());
    }

    /// @inheritdoc ISwapper
    function claimAndSwap(
        Claim calldata _claim,
        Action[] calldata _actions,
        uint256 _pct
    )
        public
        nonReentrant
        returns (uint256 diff, uint256 tokenId)
    {
        // make sure percentage is never more than 100.
        if (_pct > 100) {
            revert PctTooBig();
        }

        address[] memory users = new address[](_claim.tokens.length);
        for (uint256 i = 0; i < _claim.tokens.length; i++) {
            users[i] = msg.sender;
        }

        uint256 beforeAmount = token.balanceOf(address(this));

        // If `_tokens`, `_amounts` and `_proofs` have incorrect size, below reverts.
        // The `user` must have set this contract as a recipient
        // for the `token` prior to calling this.
        // At this point, this contract holds balances on `_tokens`.
        rewardDistributor.claim(users, _claim.tokens, _claim.amounts, _claim.proofs);

        // call actions
        (bool success,) = executor.delegatecall(
            abi.encodeCall(IExecutor.execute, (bytes32(uint256(uint160(address(this)))), _actions, 0))
        );
        if (!success) {
            revert ActionsFailed();
        }

        uint256 afterAmount = token.balanceOf(address(this));

        diff = afterAmount - beforeAmount;
        Locked memory lock;

        // If diff > 0, then kat token balance was increased on this contract.
        // If pct > 0, create a lock with percentage and send rest to sender.
        // If pct = 0, send whole amount to sender.
        if (diff > 0) {
            uint256 remaining = diff;
            if (_pct > 0) {
                lock.amount = (diff * _pct) / 100;
                remaining = diff - lock.amount;

                // 1. approve should not revert even for non-compliant ERC20s as
                // it only approves the exact amount that will be transfered
                // from this contract, automatically setting allowance back to 0.
                // we trust that escrow's createLockFor will transfer the whole lock.amount.
                // 2. It's better to allow fail rather than silently succeed if `lock.amount`
                // is less than minDeposit of escrow, so no need to add extra check and revert.
                token.approve(address(escrow), lock.amount);
                lock.tokenId = escrow.createLockFor(lock.amount, msg.sender);
            }

            if (remaining > 0) {
                token.safeTransfer(msg.sender, remaining);
            }
        }

        emit ClaimAndSwapped(msg.sender, _claim.tokens, _claim.amounts, _pct, lock);

        return (diff, lock.tokenId);
    }
}
