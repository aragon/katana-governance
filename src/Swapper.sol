// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

contract Swapper {
    using SafeERC20 for IERC20;

    GaugeVoter public voter;
    IRewardsDistributor public rewardDistributor;
    AvKATVault public vault;
    address public executor;
    address public kat;

    constructor(address _rewardDistributor, address _vault, address _executor) public {
        rewardDistributor = IRewardsDistributor(_rewardDistributor);
        vault = AvKATVault(_vault);
        executor = _executor;
        kat = vault.asset();
    }

    // Normal user calls this.
    function claimAndSwap(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs,
        Action[] calldata _actions,
        address _outputToken
    )
        public
        returns (uint256)
    {
        address[] memory users = new address[](_tokens.length);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = msg.sender;
        }

        uint256 beforeBalance = IERC20(_outputToken).balanceOf(address(this));

        // The `user` must have set this contract as a recipient
        // for the `token` prior to calling this.
        // At this point, this contract holds balances on `_tokens`.
        rewardDistributor.claim(users, _tokens, _amounts, _proofs);

        (bool success, bytes memory data) = executor.delegatecall(
            abi.encodeCall(Executor.execute, (bytes32(uint256(uint160(address(this)))), _actions, 0))
        );

        // At this point, this contract holds balances on specific token(kat) that swap occured into.
        uint256 afterBalance = IERC20(_outputToken).balanceOf(address(this));
        uint256 diff = afterBalance - beforeBalance;

        // send the difference to the caller.
        if (diff > 0) {
            IERC20(kat).safeTransfer(msg.sender, diff);
        }

        return diff;
    }
}
