// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { VotingEscrow, GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";

import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";

contract AutoCompoundStrategy is DaoAuthorizable {
    GaugeVoter public immutable voter;
    AvKATVault public immutable vault;
    Swapper public immutable swapper;
    address public immutable token;

    bytes32 public constant AUTOCOMPOUND_STRATEGY_ADMIN_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_ADMIN_ROLE");

    constructor(
        address _dao,
        address _escrow,
        address _swapper,
        address _vault,
        address _rewardDistributor
    )
        DaoAuthorizable(IDAO(_dao))
    {
        voter = GaugeVoter(VotingEscrow(_escrow).voter());
        swapper = Swapper(_swapper);

        vault = AvKATVault(_vault);
        token = vault.asset();

        // As the caller on distributor's `claim` function will be swapper,
        // it can only work if this contract allowed swapper to claim on behalf.
        IRewardsDistributor(_rewardDistributor).toggleOperator(address(this), _swapper);
    }

    /// @notice Votes on gauge voter with `_votes`.
    /// @param _votes The gauges and their weights to vote for.
    function vote(GaugeVoter.GaugeVote[] calldata _votes) external auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) {
        voter.vote(_votes);
    }

    /// @notice Claims and swaps token. In the end, deposits into vault the kat token
    ///         that it was either claimed or swapped into.
    /// @param _tokens Which tokens to claim.
    /// @param _amounts How much to claim for each token.
    /// @param _proofs The merkle proof that this contract holds `_amounts` on merkle distributor.
    /// @param _actions The actions that Swapper contract executes. Most times, it will be swap actions.
    /// @return Returns shares that were minted in exchange for depositting kat tokens.
    function claimAndCompound(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs,
        Action[] calldata _actions
    )
        external
        returns (uint256)
    {
        // Always get whole amount so we can deposit in vault.
        ISwapper.AutoCompound memory compoundConfig = ISwapper.AutoCompound(false, 0);

        // which tokens to claim for with their proofs and amounts.
        ISwapper.Claim memory claimTokens = ISwapper.Claim(_tokens, _amounts, _proofs);

        (uint256 claimedAmount,) = swapper.claimAndSwap(claimTokens, _actions, compoundConfig);

        // If claimedAmount is greater than 0, autocompound received some amounts on `token`.
        // Hence automatically deposit it into vault. Requires approval before deposit.
        if (claimedAmount > 0) {
            IERC20(token).approve(address(vault), claimedAmount);
            return vault.deposit(claimedAmount, address(this));
        }

        return 0;
    }
}
