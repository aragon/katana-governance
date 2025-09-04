// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";
import { AvKATVault } from "../../../src/AvKATVault.sol";
import { console2 as console } from "forge-std/console2.sol";

contract VaultWithdrawTest is Base {
    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), type(uint256).max / 3);
        _mintAndApprove(alice, address(escrow), type(uint256).max / 3);
    }

    function test_withdraw() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        // Alice deposits 100
        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        // before amounts
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsBefore = token.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);

        // Alice withdraws 50
        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // after amounts
        assertEq(vault.balanceOf(alice), sharesBefore - shares);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_withdrawsToReceiver() public {
        address receiver = address(456);

        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        // `deposit` burns (reduces supply due to merge),
        // so withdraw mints the next id after the burned one → +2
        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.expectEmit();
        emit TokenIdWithdrawn(expectedTokenId, receiver);

        vault.withdraw(withdrawAmount, receiver, alice);
        vm.stopPrank();

        assertEq(lockNft.ownerOf(expectedTokenId), receiver);
        assertEq(escrow.locked(expectedTokenId).amount, withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_withdrawWithAllowance() public {
        // alice deposits
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        // alice approves bob
        vault.approve(bob, withdrawAmount);
        vm.stopPrank();

        // bob withdraws on behalf of alice
        vm.startPrank(bob);
        vault.withdraw(withdrawAmount, bob, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), withdrawAmount);
        assertEq(vault.allowance(alice, bob), 0);
    }
}
