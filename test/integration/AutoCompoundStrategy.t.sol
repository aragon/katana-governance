// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { IAddressGaugeVote as IGaugeVoter } from "@voting/IAddressGaugeVoter.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { AutoCompoundStrategy } from "src/AutoCompoundStrategy.sol";

import { MockSwap } from "test/mocks/MockSwap.sol";

contract AutoCompoundTest is Base {
    address[] internal tokens;
    uint256[] internal amounts;

    address internal gaugeA = vm.createWallet("gaugeA").addr;
    address internal gaugeB = vm.createWallet("gaugeB").addr;

    function setUp() public override {
        super.setUp();

        tokens.push(tokenA);
        tokens.push(tokenB);

        amounts.push(50e18);
        amounts.push(15e18);

        vm.startPrank(address(dao));
        voter.createGauge(gaugeA, "metadata1");
        voter.createGauge(gaugeB, "metadata2");
        vm.stopPrank();
    }

    function testRevert_VoteIfNoPermission() public {
        vm.expectRevert();
        vm.prank(address(1));
        autoCompoundStrategy.vote(new GaugeVoter.GaugeVote[](0));
    }

    // tokenA swaps into token and tokenB swaps into token
    function test_ClaimsAndCompoundsAutomaticallyIfClaimedAmountIsNonZero() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(autoCompoundStrategy), tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, address(token), new uint256[](0));

        uint256 shares = autoCompoundStrategy.claimAndCompound(tokens, amounts, proofs, actions);
        assertNotEq(shares, 0);
    }

    // tokenA swaps into tokenC and tokenB swaps into tokenC
    function test_ClaimsTokensButDoesnotDepositInVault() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(autoCompoundStrategy), tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, tokenC, new uint256[](0));

        uint256 shares = autoCompoundStrategy.claimAndCompound(tokens, amounts, proofs, actions);
        assertEq(shares, 0);
    }

    function test_Votes() public {
        // To create a master token id, vault starts with already predefined amount.
        // Hence, vault already has assets in it. This means we can vote as vp > 0.
        GaugeVoter.GaugeVote[] memory votes = new IGaugeVoter.GaugeVote[](2);
        votes[0] = IGaugeVoter.GaugeVote(50, gaugeA);
        votes[1] = IGaugeVoter.GaugeVote(40, gaugeB);

        autoCompoundStrategy.vote(votes);

        uint256 gaugeAVotesBefore = voter.votes(address(autoCompoundStrategy), gaugeA);
        uint256 gaugeBVotesBefore = voter.votes(address(autoCompoundStrategy), gaugeB);

        assertNotEq(gaugeAVotesBefore, 0);
        assertNotEq(gaugeBVotesBefore, 0);

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(autoCompoundStrategy), tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, address(token), new uint256[](0));

        autoCompoundStrategy.claimAndCompound(tokens, amounts, proofs, actions);

        // At this point, tokens got claimed and autocompounding caused
        // increase of assets in vault. Though, it shouldn't cause auto-vote
        // as we only update vp votes when new votes become less than current one.
        assertEq(voter.votes(address(autoCompoundStrategy), gaugeA), gaugeAVotesBefore);
        assertEq(voter.votes(address(autoCompoundStrategy), gaugeB), gaugeBVotesBefore);

        autoCompoundStrategy.vote(votes);

        // We voted manually, so new votes for each gauge must be bigger.
        assertGt(voter.votes(address(autoCompoundStrategy), gaugeA), gaugeAVotesBefore);
        assertGt(voter.votes(address(autoCompoundStrategy), gaugeB), gaugeBVotesBefore);
    }

    // ============= Upgrade Tests =============

    function testRevert_UpgradeUnauthorized() public {
        address newImplementation = address(new AutoCompoundStrategy());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(autoCompoundStrategy),
                address(alice),
                AutoCompoundStrategy(newImplementation).AUTOCOMPOUND_STRATEGY_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        autoCompoundStrategy.upgradeTo(newImplementation);
    }

    function test_UpgradeAuthorized() public {
        address newImplementation = address(new AutoCompoundStrategy());

        // Upgrade should succeed
        autoCompoundStrategy.upgradeTo(address(newImplementation));

        assertEq(autoCompoundStrategy.implementation(), address(newImplementation));
    }
}
