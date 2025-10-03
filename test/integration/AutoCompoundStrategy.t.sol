// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { IAddressGaugeVote as IGaugeVoter } from "@voting/IAddressGaugeVoter.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { AutoCompoundStrategy } from "src/strategies/AutoCompoundStrategy.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IStrategyNFT } from "src/interfaces/IStrategyNFT.sol";

import { deployAutoCompoundStrategy } from "src/utils/Deployers.sol";

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

    function test_SetDelegatee() public {
        address newDelegatee = address(0x123);

        acStrategy.delegate(newDelegatee);

        assertEq(acStrategy.delegatee(), newDelegatee);

        // Check delegation happened
        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, newDelegatee);
    }

    function testRevert_SetDelegateeIfNoPermission() public {
        vm.expectRevert();
        vm.prank(address(1));
        acStrategy.delegate(address(0x123));
    }

    function testRevert_VoteIfNoPermission() public {
        vm.expectRevert();
        vm.prank(address(1));
        acStrategy.vote(new GaugeVoter.GaugeVote[](0));
    }

    // tokenA swaps into token and tokenB swaps into token
    function test_ClaimsAndCompoundsAutomaticallyIfClaimedAmountIsNonZero() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        uint256 shares = acStrategy.claimAndCompound(tokens, amounts, proofs, actions);
        assertNotEq(shares, 0);
    }

    // tokenA swaps into tokenC and tokenB swaps into tokenC
    function test_ClaimsTokensButDoesnotDepositInVault() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(tokens, amounts, tokenC, address(swapper));

        uint256 shares = acStrategy.claimAndCompound(tokens, amounts, proofs, actions);
        assertEq(shares, 0);
    }

    // Helper to create gauge votes
    function _createGaugeVotes() internal view returns (GaugeVoter.GaugeVote[] memory) {
        GaugeVoter.GaugeVote[] memory votes = new IGaugeVoter.GaugeVote[](2);
        votes[0] = IGaugeVoter.GaugeVote(50, gaugeA);
        votes[1] = IGaugeVoter.GaugeVote(40, gaugeB);
        return votes;
    }

    // User gets delegated and votes on gauge voter directly.
    function test_DelegatesOtherAndVotes() public {
        // Set up delegatee EOA
        address delegatee = address(0xDEAD);
        acStrategy.delegate(delegatee);

        // Verify delegation
        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, delegatee);

        // Now the delegatee can vote directly on the voter with strategy's voting power
        GaugeVoter.GaugeVote[] memory votes = _createGaugeVotes();

        vm.prank(delegatee);
        voter.vote(votes);

        uint256 gaugeAVotesBefore = voter.votes(delegatee, gaugeA);
        uint256 gaugeBVotesBefore = voter.votes(delegatee, gaugeB);

        assertNotEq(gaugeAVotesBefore, 0);
        assertNotEq(gaugeBVotesBefore, 0);

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        acStrategy.claimAndCompound(tokens, amounts, proofs, actions);

        // After compounding, delegatee can vote again with increased voting power
        vm.prank(delegatee);
        voter.vote(votes);

        // Voting power increased due to compounding
        assertGt(voter.votes(delegatee, gaugeA), gaugeAVotesBefore);
        assertGt(voter.votes(delegatee, gaugeB), gaugeBVotesBefore);
    }

    // AcStrategy gets delegated to itself and votes.
    function test_DelegatesItselfAndVotes_WithoutCompounding() public {
        // Strategy delegates to itself
        acStrategy.delegate(address(acStrategy));

        // Verify self-delegation
        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, address(acStrategy));

        // Strategy can now vote directly
        GaugeVoter.GaugeVote[] memory votes = _createGaugeVotes();
        acStrategy.vote(votes);

        // Verify votes were cast
        uint256 gaugeAVotes = voter.votes(address(acStrategy), gaugeA);
        uint256 gaugeBVotes = voter.votes(address(acStrategy), gaugeB);

        assertNotEq(gaugeAVotes, 0);
        assertNotEq(gaugeBVotes, 0);
    }

    function test_VoteDirectlyAfterCompounding() public {
        // Strategy delegates to itself
        acStrategy.delegate(address(acStrategy));

        // Initial vote
        GaugeVoter.GaugeVote[] memory votes = _createGaugeVotes();
        acStrategy.vote(votes);

        uint256 gaugeAVotesBefore = voter.votes(address(acStrategy), gaugeA);
        uint256 gaugeBVotesBefore = voter.votes(address(acStrategy), gaugeB);

        // Compound to increase voting power
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        acStrategy.claimAndCompound(tokens, amounts, proofs, actions);

        // Vote again with increased voting power
        acStrategy.vote(votes);

        // Voting power increased due to compounding
        assertGt(voter.votes(address(acStrategy), gaugeA), gaugeAVotesBefore);
        assertGt(voter.votes(address(acStrategy), gaugeB), gaugeBVotesBefore);
    }

    // ============= Upgrade Tests =============

    function testRevert_UpgradeUnauthorized() public {
        address newImplementation = address(new AutoCompoundStrategy());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(acStrategy),
                address(alice),
                AutoCompoundStrategy(newImplementation).AUTOCOMPOUND_STRATEGY_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        acStrategy.upgradeTo(newImplementation);
    }

    function test_UpgradeAuthorized() public {
        address newImplementation = address(new AutoCompoundStrategy());

        // Upgrade should succeed
        acStrategy.upgradeTo(address(newImplementation));

        assertEq(acStrategy.implementation(), address(newImplementation));
    }

    // ============= Error Tests =============

    function testRevert_OnlyVaultCanCall_Withdraw() public {
        vm.expectRevert(IStrategy.OnlyVaultCanCall.selector);
        vm.prank(alice);
        acStrategy.withdraw(alice, 100e18);
    }

    function testRevert_OnlyVaultCanCall_DepositTokenId() public {
        vm.expectRevert(IStrategy.OnlyVaultCanCall.selector);
        vm.prank(alice);
        acStrategy.depositTokenId(1);
    }

    function testRevert_OnlyVaultCanCall_RetireStrategy() public {
        vm.expectRevert(IStrategy.OnlyVaultCanCall.selector);
        vm.prank(alice);
        acStrategy.retireStrategy();
    }

    function testRevert_MasterTokenNotSet_Withdraw() public {
        // Deploy a new strategy without master token set
        (, address newStrategy) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );

        vm.expectRevert(IStrategyNFT.MasterTokenNotSet.selector);
        vm.prank(address(vault));
        AutoCompoundStrategy(newStrategy).withdraw(alice, 100e18);
    }

    function testRevert_MasterTokenNotSet_DepositTokenId() public {
        // Deploy a new strategy without master token set
        (, address newStrategy) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );

        vm.expectRevert(IStrategyNFT.MasterTokenNotSet.selector);
        vm.prank(address(vault));
        AutoCompoundStrategy(newStrategy).depositTokenId(1);
    }
}
