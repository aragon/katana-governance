// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";

contract VaultRedeemTest is Base {
    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), type(uint256).max / 3);
        _mintAndApprove(alice, address(escrow), type(uint256).max / 3);
    }

    function test_redeem() public {
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        // Alice deposits 100
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // before amounts
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsBefore = escrowToken.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);

        // Alice redeems 50
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 assets = vault.redeem(withdrawAmount, alice, alice);

        // after amounts
        assertEq(assets, _parseToken(50));
        assertEq(vault.balanceOf(alice), sharesBefore - assets);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_redeemsToReceiver() public {
        address receiver = address(456);

        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        // alice deposits 100
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        // `deposit` burns (reduces supply due to merge),
        // so withdraw mints the next id after the burned one → +2
        uint256 lastIndex = lockNft.totalSupply() - 1;
        uint256 expectedTokenId = lockNft.tokenByIndex(lastIndex) + 2;

        vm.expectEmit();
        emit Vault.TokenIdWithdrawn(expectedTokenId, receiver);

        // alice redeems and specifies `receiver` as recipient.
        vm.prank(alice);
        uint256 assets = vault.redeem(withdrawAmount, receiver, alice);

        assertEq(assets, _parseToken(50));
        assertEq(lockNft.ownerOf(expectedTokenId), receiver);
        assertEq(escrow.locked(expectedTokenId).amount, withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_redeemsWithAllowance() public {
        // alice deposits
        uint256 depositAmount = _parseToken(100);
        uint256 withdrawAmount = _parseToken(50);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        // alice approves bob
        vault.approve(bob, depositAmount);
        vm.stopPrank();

        // bob redeems on behalf of alice
        vm.prank(bob);
        uint256 assets = vault.redeem(withdrawAmount, bob, alice);

        assertEq(assets, _parseToken(50));
        uint256 remaining = depositAmount - withdrawAmount;
        assertEq(vault.balanceOf(alice), remaining);
        assertEq(vault.allowance(alice, bob), remaining);
    }
}
