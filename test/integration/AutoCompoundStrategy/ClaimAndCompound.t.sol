// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AutoCompoundBase } from "./AutoCompoundBase.t.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import { PayableReceiver } from "../../mocks/PayableReceiver.sol";

contract AutoCompoundClaimTest is AutoCompoundBase {
    function testRevert_NoPermission() public {
        // Setup claim data
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        // Try to call without permission - should revert with DaoUnauthorized
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(acStrategy),
                alice,
                acStrategy.AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE()
            )
        );
        vm.prank(alice);
        acStrategy.claimAndCompound(tokens, amounts, proofs, actions);
    }

    function testRevert_IfAtLeastOneActionFails() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);

        Action[] memory actions = new Action[](1);
        actions[0].to = address(this);
        actions[0].data = "0x11111111";

        vm.expectRevert();
        acStrategy.claimAndCompound(tokens, amounts, proofs, actions);
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

    function test_ClaimAndCompoundAfterDelegation() public {
        // Delegate to an address and then claim and compound
        address delegatee = address(0xDEAD);
        acStrategy.delegate(delegatee);

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);
        Action[] memory actions =
            swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper));

        uint256 totalSharesBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 shares = acStrategy.claimAndCompound(tokens, amounts, proofs, actions);

        assertNotEq(shares, 0);
        assertEq(vault.totalSupply(), totalSharesBefore);
        assertGt(vault.totalAssets(), totalAssetsBefore);
    }

    function test_ClaimAndCompoundWithEthValue() public {
        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(address(acStrategy), tokens, amounts);

        // Create a mock payable contract to receive ETH
        PayableReceiver receiver = new PayableReceiver();

        // Create actions: one to send ETH, and the rest to swap tokens
        Action[] memory actions = new Action[](3);
        actions[0] = Action({ to: address(receiver), value: 0.5 ether, data: abi.encodeWithSignature("receiveEth()") });
        actions[1] = swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper))[0];
        actions[2] = swapActionsBuilder.buildSwapActions(tokens, amounts, address(escrowToken), address(swapper))[1];

        // Fund the strategy with ETH
        vm.deal(address(this), 1 ether);

        uint256 receiverBalanceBefore = address(receiver).balance;

        // Call claimAndCompound with ETH value
        acStrategy.claimAndCompound{ value: 0.5 ether }(tokens, amounts, proofs, actions);

        assertEq(address(receiver).balance, receiverBalanceBefore + 0.5 ether, "Receiver should have received ETH");
    }
}
