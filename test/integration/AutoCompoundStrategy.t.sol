// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "./Base.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { IAddressGaugeVote as IGaugeVoter } from "@voting/IAddressGaugeVoter.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { MockSwap } from "../mocks/MockSwap.sol";

contract AutoCompoundTest is Base {
    function setUp() public override {
        super.setUp();

        super.buildMerkleTree(address(autoCompoundStrategy), 50e18, 15e18);
    }

    function testRevert_VoteIfNoPermission() public {
        vm.expectRevert();
        vm.prank(address(1));
        autoCompoundStrategy.vote(new GaugeVoter.GaugeVote[](0));
    }

    function test_ClaimsAndCompoundsAutomaticallyIfClaimedAmountIsNonZero() public {
        // tokenA swaps into token and tokenB swaps into token
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            claimAndSwapParams(tokenA, address(token), tokenB, address(token));

        uint256 shares = autoCompoundStrategy.claimAndCompound(tokens, amounts, proofs, actions);
        assertNotEq(shares, 0);
    }

    function test_ClaimsTokensButDoesnotDepositInVault() public {
        // tokenA swaps into tokenC and tokenB swaps into tokenC
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            claimAndSwapParams(tokenA, tokenC, tokenB, tokenC);

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

        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            claimAndSwapParams(tokenA, address(token), tokenB, address(token));

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

    function claimAndSwapParams(
        address claim1,
        address swap1,
        address claim2,
        address swap2
    )
        internal
        view
        returns (address[] memory, uint256[] memory, bytes32[][] memory, Action[] memory)
    {
        ClaimInput[] memory input = new ClaimInput[](2);
        input[0] = ClaimInput(address(claim1), 50e18, merkleTree.getProof(leaves, 0));
        input[1] = ClaimInput(address(claim2), 15e18, merkleTree.getProof(leaves, 1));

        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs) = buildClaimAndSwapParams(input);

        // Swap routes
        Action[] memory actions = new Action[](2);
        actions[0].to = address(mockSwap);
        actions[0].data = abi.encodeCall(MockSwap.swap, (address(claim1), address(swap1), 50e18));

        actions[1].to = address(mockSwap);
        actions[1].data = abi.encodeCall(MockSwap.swap, (address(claim2), address(swap2), 15e18));

        return (tokens, amounts, proofs, actions);
    }
}
