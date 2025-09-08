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

contract AutoCompoundStrategy {
    GaugeVoter public voter;
    AvKATVault public vault;
    Swapper public swapper;

    constructor(address _gaugeVoter, address _swapper, address _vault) public {
        voter = GaugeVoter(_gaugeVoter);
        vault = AvKATVault(_vault);
        swapper = Swapper(_swapper);
    }

    function vote(GaugeVoter.GaugeVote[] calldata _votes) external {
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
        uint256 claimedAmount = swapper.claimAndSwap(_tokens, _amounts, _proofs, _actions);
        if (claimedAmount > 0) {
            vault.deposit(claimedAmount, address(this));
        }
    }
}
