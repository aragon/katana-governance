// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { VotingEscrow, EscrowIVotesAdapter, GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { AvKATVault } from "./AvKATVault.sol";
import { Swapper } from "./Swapper.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";

contract AutoCompoundStrategy is DaoAuthorizable {
    GaugeVoter public immutable voter;
    AvKATVault public immutable vault;
    Swapper public immutable swapper;
    address public immutable token;

    bytes32 public constant AUTOCOMPOUND_STRATEGY_ADMIN_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_ADMIN_ROLE");

    constructor(
        address _dao,
        address _gaugeVoter,
        address _swapper,
        address _vault,
        address _rewardDistributor
    )
        DaoAuthorizable(IDAO(_dao))
    {
        voter = GaugeVoter(_gaugeVoter);
        vault = AvKATVault(_vault);
        swapper = Swapper(_swapper);
        token = vault.asset();

        // As the caller on distributor's `claim` function will be swapper,
        // it can only work if this contract allowed swapper to claim on behalf.
        IRewardsDistributor(_rewardDistributor).toggleOperator(address(this), _swapper);
    }

    function vote(GaugeVoter.GaugeVote[] calldata _votes) external auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) {
        voter.vote(_votes);
    }

    function claimAndCompound(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs,
        Action[] calldata _actions
    )
        external
    {
        uint256 claimedAmount = swapper.claimAndSwap(_tokens, _amounts, _proofs, _actions, token);
        if (claimedAmount > 0) {
            vault.deposit(claimedAmount, address(this));
        }
    }
}
