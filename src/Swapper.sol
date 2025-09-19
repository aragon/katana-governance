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
import { console2 as console } from "forge-std/console2.sol";

contract Swapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ActionsFailed();
    error NoBalanceChange();
    error ZeroAddress();

    IRewardsDistributor public immutable rewardDistributor;
    AvKATVault public immutable vault;
    address public immutable executor;
    address public immutable kat;

    constructor(address _rewardDistributor, address _vault, address _executor) public {
        if (_executor == address(0)) {
            revert ZeroAddress();
        }

        rewardDistributor = IRewardsDistributor(_rewardDistributor);
        vault = AvKATVault(_vault);
        executor = _executor;
        kat = vault.asset();
    }

    /// @param _tokens The token addresses that caller wants to claim.
    /// @param _amounts How much to claim for each token.
    /// @param _proofs The merkle proof for each token that user really has funds.
    /// @param _actions The custom actions used to swap tokens in `_outputToken`.
    /// @param _outputToken The token that all `_tokens` gets swapped into.
    ///                     All the swapped amounts end up on `_outputToken`
    ///                     which is sent to the caller.
    function claimAndSwap(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs,
        Action[] calldata _actions,
        address _outputToken
    )
        public
        nonReentrant
        returns (uint256)
    {
        address[] memory users = new address[](_tokens.length);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = msg.sender;
        }

        uint256 beforeBalance = IERC20(_outputToken).balanceOf(address(this));

        // `rewardDistributor` would revert if array length mismatch occurs.
        // The `user` must have set this contract as a recipient
        // for the `token` prior to calling this.
        // At this point, this contract holds balances on `_tokens`.
        rewardDistributor.claim(users, _tokens, _amounts, _proofs);

        (bool success,) = executor.delegatecall(
            abi.encodeCall(Executor.execute, (bytes32(uint256(uint160(address(this)))), _actions, 0))
        );
        if (!success) {
            revert ActionsFailed();
        }

        // At this point, this contract holds balances on specific token(kat) that swap occured into.
        uint256 afterBalance = IERC20(_outputToken).balanceOf(address(this));
        uint256 diff = afterBalance - beforeBalance;

        if (diff == 0) {
            revert NoBalanceChange();
        }

        // send the difference to the caller.
        IERC20(_outputToken).safeTransfer(msg.sender, diff);

        return diff;
    }
}
