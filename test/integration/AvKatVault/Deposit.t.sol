// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVotingEscrowCoreErrors } from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";

contract VaultDepositTest is Base {
    using ProxyLib for address;

    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), type(uint256).max / 3);
        _mintAndApprove(alice, address(escrow), type(uint256).max / 3);
    }

    function testRevert_IfMasterTokenNotSet() public {
        address base = address(new Vault());

        Vault newVault = Vault(
            base.deployUUPSProxy(
                abi.encodeCall(Vault.initialize, (address(dao), address(escrow), address(0), "Test Vault", "TEST"))
            )
        );

        vm.startPrank(alice);
        escrowToken.approve(address(newVault), _parseToken(100));

        vm.expectRevert(Vault.MasterTokenNotSet.selector);
        newVault.deposit(_parseToken(100), alice);
        vm.stopPrank();
    }

    function testRevert_IfNotOwner() public {
        vm.startPrank(alice);
        escrowToken.approve(address(escrow), _parseToken(50));
        uint256 tokenId = escrow.createLock(_parseToken(50));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert();
        vault.depositToken(tokenId, bob);
        vm.stopPrank();
    }

    function testRevert_DepositsToZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(_parseToken(100), address(0));
    }

    function testRevert_IfZeroAmount() public {
        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_vaultEmpty() public view {
        uint256 amount = escrow.locked(masterTokenId).amount;

        assertEq(vault.totalAssets(), amount);
        assertEq(vault.totalSupply(), amount);
    }

    function test_DepositToken() public {
        uint256 depositAmount = _parseToken(50);

        uint256 assetBefore = escrowToken.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(depositAmount);
        lockNft.setApprovalForAll(address(vault), true);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, depositAmount, depositAmount);

        uint256 shares = vault.depositToken(tokenId, alice);
        vm.stopPrank();

        uint256 totalAssetsAfter = totalAssetsBefore + depositAmount;

        assertEq(vault.balanceOf(alice), sharesBefore + depositAmount);
        assertEq(vault.totalAssets(), totalAssetsAfter);
        assertEq(escrowToken.balanceOf(alice), assetBefore - depositAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsAfter);
        assertEq(shares, depositAmount);
    }

    function test_Deposit() public {
        uint256 depositAmount = _parseToken(100);

        uint256 assetBefore = escrowToken.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.expectEmit();
        emit IERC4626.Deposit(alice, alice, depositAmount, depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 totalAssetsAfter = totalAssetsBefore + depositAmount;

        assertEq(vault.balanceOf(alice), sharesBefore + shares);
        assertEq(vault.totalAssets(), totalAssetsAfter);
        assertEq(escrowToken.balanceOf(alice), assetBefore - depositAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsAfter);

        assertEq(shares, depositAmount);
    }

    function test_DepositsToReceiver() public {
        address receiver = vm.createWallet("receiver").addr;

        uint256 depositAmount = _parseToken(100);

        vm.expectEmit();
        emit IERC4626.Deposit(alice, receiver, depositAmount, depositAmount);

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, receiver);

        assertEq(vault.balanceOf(receiver), shares);
    }
}
