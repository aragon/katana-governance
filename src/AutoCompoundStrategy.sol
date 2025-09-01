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
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { AvKATVault } from "./AvKATVault.sol";

contract AutoCompoundStrategy {
    GaugeVoter public voter;
    IRewardsDistributor public rewardDistributor;
    AvKATVault public vault;

    constructor(address _gaugeVoter, address _rewardDistributor, address _vault) public {
        voter = GaugeVoter(_gaugeVoter);
        rewardDistributor = IRewardsDistributor(_rewardDistributor);
        vault = AvKATVault(_vault);
    }

    function vote(GaugeVoter.GaugeVote[] calldata _votes) external {
        voter.vote(_votes);
    }

    function claimAndCompound() external {
        uint256 claimedAmount = rewardDistributor.claim();

        VotingEscrow escrow = VotingEscrow(voter.escrow());

        uint256 tokenId = escrow.createLockFor(claimedAmount, address(vault));
        escrow.merge(tokenId, vault.masterTokenId());
    }
}
