// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { Base } from "./Base.sol";
import { MerkleTree } from "@merkl/Distributor.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Errors } from "@merkl/utils/Errors.sol";
import { MockSwap } from "../mocks/MockSwap.sol";
// import { MerkleTree } from "@openzeppelin/contracts/utils/structs/MerkleTree.sol";

contract SwapperTest is Base {
    bytes32 internal root;
    bytes32[] internal leaves;

    struct ClaimInput {
        address token;
        uint256 amount;
        bytes32[] proof;
    }

    function setUp() public override {
        super.setUp();

        // Setup leaves.
        // Alice   has 50e18 on tokenA and 15e18 on tokenB
        // Bob     has 80e18 on tokenA
        // Charlie has 20e18 on tokenB
        leaves.push(keccak256(abi.encode(alice, tokenA, 50e18)));
        leaves.push(keccak256(abi.encode(alice, tokenB, 15e18)));
        leaves.push(keccak256(abi.encode(bob, tokenA, 80e18)));
        leaves.push(keccak256(abi.encode(charlie, tokenB, 20e18)));

        root = merkleTree.getRoot(leaves);

        merklDistributor.updateTree(MerkleTree({ merkleRoot: root, ipfsHash: bytes32(0) }));

        // Each user has to allow swapper to claim.
        vm.startPrank(alice);
        merklDistributor.setClaimRecipient(address(swapper), address(tokenA));
        merklDistributor.setClaimRecipient(address(swapper), address(tokenB));
        vm.stopPrank();

        vm.prank(bob);
        merklDistributor.setClaimRecipient(address(swapper), address(tokenA));

        vm.prank(charlie);
        merklDistributor.setClaimRecipient(address(swapper), address(tokenB));

        vm.warp(merklDistributor.endOfDisputePeriod() + 1);

        vm.startPrank(address(swapper));
        tokenA.approve(address(mockSwap), type(uint192).max);
        tokenB.approve(address(mockSwap), type(uint192).max);
        vm.stopPrank();
    }

    function testRevert_IfInvalidProof() public {
        ClaimInput[] memory input = new ClaimInput[](2);

        // 2nd claim is invalid as index must be 1.
        input[0] = ClaimInput(address(tokenA), 50e18, merkleTree.getProof(leaves, 0));
        input[1] = ClaimInput(address(tokenB), 15e18, merkleTree.getProof(leaves, 2));
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs) = getClaimAndSwapParams(input);
        Action[] memory actions = new Action[](0);

        vm.expectRevert(Errors.InvalidProof.selector);
        vm.prank(alice, alice);
        swapper.claimAndSwap(tokens, amounts, proofs, actions, address(token));
    }

    function test_ClaimsAndSwapsSuccessfully() public {
        ClaimInput[] memory input = new ClaimInput[](2);
        // valid proof
        input[0] = ClaimInput(address(tokenA), 50e18, merkleTree.getProof(leaves, 0));
        input[1] = ClaimInput(address(tokenB), 15e18, merkleTree.getProof(leaves, 1));
        (address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs) = getClaimAndSwapParams(input);

        // Swap routes
        Action[] memory actions = new Action[](2);
        actions[0].to = address(mockSwap);
        actions[0].data = abi.encodeCall(MockSwap.swap, (address(tokenA), address(token), 50e18));

        actions[1].to = address(mockSwap);
        actions[1].data = abi.encodeCall(MockSwap.swap, (address(tokenB), address(token), 15e18));

        assertEq(token.balanceOf(alice), 0);
        vm.prank(alice, alice);
        swapper.claimAndSwap(tokens, amounts, proofs, actions, address(token));

        assertEq(token.balanceOf(alice), 130e18);
    }

    function getClaimAndSwapParams(ClaimInput[] memory _claims)
        internal
        returns (address[] memory, uint256[] memory, bytes32[][] memory)
    {
        address[] memory tokens = new address[](_claims.length);
        uint256[] memory amounts = new uint256[](_claims.length);
        bytes32[][] memory proofs = new bytes32[][](_claims.length);

        for (uint256 i; i < _claims.length; ++i) {
            tokens[i] = _claims[i].token;
            amounts[i] = _claims[i].amount;
            proofs[i] = _claims[i].proof;
        }

        return (tokens, amounts, proofs);
    }
}
