// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { VotingEscrow, GaugeVoter } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";

contract AutoCompoundStrategy is Initializable, DaoAuthorizable {
    ///@notice The bytes32 identifier for admin role functions.
    bytes32 public constant AUTOCOMPOUND_STRATEGY_ADMIN_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_ADMIN_ROLE");

    /// @notice The gauge voter where this contract votes for gauges.
    GaugeVoter public voter;

    /// @notice The vault address where this contract auto-compounds(deposits kat).
    AvKATVault public vault;

    /// @notice The swapper contract which this contract asks for claiming tokens.
    Swapper public swapper;

    /// @notice The token contract that vault uses as assets.
    address public token;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        address _swapper,
        address _vault,
        address _rewardDistributor
    )
        external
        initializer
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

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
        // which tokens to claim for with their proofs and amounts.
        ISwapper.Claim memory claimTokens = ISwapper.Claim(_tokens, _amounts, _proofs);

        (uint256 claimedAmount,) = swapper.claimAndSwap(claimTokens, _actions, 0);

        // If claimedAmount is greater than 0, autocompound received some amounts on `token`.
        // Hence automatically deposit it into vault. Requires approval before deposit.
        if (claimedAmount > 0) {
            IERC20(token).approve(address(vault), claimedAmount);
            return vault.deposit(claimedAmount, address(this));
        }

        return 0;
    }
}
