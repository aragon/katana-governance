// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { Base } from "./Base.sol";
import { MerkleTree } from "@merkl/Distributor.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Errors } from "@merkl/utils/Errors.sol";
import { MockSwap } from "../mocks/MockSwap.sol";
import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract SwapperTest is Base {
    function setUp() public override {
        super.setUp();

        super.buildMerkleTree(alice, 50e18, 15e18);
    }

    function testRevert_IfAutoCompoundConfigInvalid() public {
        Action[] memory actions = new Action[](0);
        ISwapper.Claim memory input = ISwapper.Claim(new address[](0), new uint256[](0), new bytes32[][](0));

        vm.expectRevert(ISwapper.WeightTooBig.selector);
        swapper.claimAndSwap(input, actions, 101);
    }

    function testRevert_IfInvalidProof() public {
        ClaimInput[] memory input = new ClaimInput[](2);

        // 2nd claim is invalid as its amount is wrong.
        input[0] = ClaimInput(address(tokenA), 50e18, merkleTree.getProof(leaves, 0));
        input[1] = ClaimInput(address(tokenB), 16e18, merkleTree.getProof(leaves, 1));
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs) = buildClaimAndSwapParams(input);

        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), new Action[](0), 0);
    }

    // both tokens are swapped into kat but autocompound is false, hence all kat tokens go to the user.
    function test_MultipleTokensSwappedAndAutoCompoundIsFalse() public {
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            AliceClaimAndSwapParams(tokenA, address(token), tokenB, address(token));

        assertEq(token.balanceOf(alice), 0);
        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, 0, ISwapper.Locked(0, 0));
        swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 0);

        assertEq(token.balanceOf(alice), 130e18);
    }

    // both tokens are swapped into kat and autocompound is true, hence
    // creates lock with some portion to locked and rest goes to user.
    function test_MultipleTokensSwappedAndCompoundIsEnabled() public {
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            AliceClaimAndSwapParams(tokenA, address(token), tokenB, address(token));

        uint256 weight = 10;
        uint256 lockAmount = (weight * 130e18) / 100;

        assertEq(token.balanceOf(alice), 0);
        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, weight, ISwapper.Locked(2, lockAmount));
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, weight);

        assertEq(diff, 130e18);
        assertEq(escrow.locked(tokenId).amount, lockAmount);
        assertEq(token.balanceOf(alice), 130e18 - lockAmount);
    }

    // Only single token is swapped into kat and compound is enabled,
    // hence some portion goes to newly created lock, rest goes to user.
    function test_SingleTokenSwappedAndCompoundIsEnabled() public {
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            AliceClaimAndSwapParams(tokenA, address(token), tokenB, tokenC);

        assertEq(token.balanceOf(alice), 0);

        uint256 weight = 10;
        uint256 lockAmount = (weight * 100e18) / 100;

        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, weight, ISwapper.Locked(2, lockAmount));
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, weight);

        assertEq(diff, 100e18);
        assertEq(escrow.locked(tokenId).amount, lockAmount);
        assertEq(token.balanceOf(alice), 100e18 - lockAmount);
    }

    // no tokens are swapped into kat, hence no kat increase on user.
    function test_NoTokenIsSwappedIntoKat() public {
        // tokenA swaps into tokenC and tokenB swaps into tokenC
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs, Action[] memory actions) =
            AliceClaimAndSwapParams(tokenA, tokenC, tokenB, tokenC);

        assertEq(token.balanceOf(alice), 0);
        vm.prank(alice, alice);
        vm.expectEmit();
        emit ISwapper.ClaimAndSwapped(alice, tokens, amounts, 10, ISwapper.Locked(0, 0));
        (uint256 diff, uint256 tokenId) = swapper.claimAndSwap(ISwapper.Claim(tokens, amounts, proofs), actions, 10);

        assertEq(token.balanceOf(alice), 0);
        assertEq(diff, 0);
    }

    // claim1 swaps into swap1
    // claim2 swaps into swap2
    function AliceClaimAndSwapParams(
        address claim1,
        address swap1,
        address claim2,
        address swap2
    )
        internal
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
