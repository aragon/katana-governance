// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVotingEscrowCoreErrors } from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";

contract VaultDepositTokenTest is Base {
    using ProxyLib for address;

    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), _parseToken(1000));
        _mintAndApprove(alice, address(escrow), _parseToken(1000));
        _mintAndApprove(bob, address(vault), _parseToken(1000));
        _mintAndApprove(bob, address(escrow), _parseToken(1000));
    }

    function testRevert_IfMasterTokenNotSet() public {
        address base = address(new Vault());

        Vault newVault = Vault(
            base.deployUUPSProxy(
                abi.encodeCall(Vault.initialize, (address(dao), address(escrow), address(0), "Test Vault", "TEST"))
            )
        );

        vm.startPrank(alice);
        escrowToken.approve(address(escrow), _parseToken(50));
        uint256 tokenId = escrow.createLock(_parseToken(50));
        lockNft.setApprovalForAll(address(newVault), true);

        vm.expectRevert(Vault.MasterTokenNotSet.selector);
        newVault.depositToken(tokenId, alice);
        vm.stopPrank();
    }

    function testRevert_IfNotOwner() public {
        vm.startPrank(alice);
        escrowToken.approve(address(escrow), _parseToken(50));
        uint256 tokenId = escrow.createLock(_parseToken(50));
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(bob);
        vault.depositToken(tokenId, bob);
    }

    function testRevert_IfNotApproved() public {
        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(_parseToken(50));

        vm.expectRevert();
        vault.depositToken(tokenId, alice);
        vm.stopPrank();
    }

    function testRevert_IfDepositToZeroReceiver() public {
        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(_parseToken(50));
        lockNft.setApprovalForAll(address(vault), true);

        vm.expectRevert();
        vault.depositToken(tokenId, address(0));
        vm.stopPrank();
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

        // Verify the token was merged (no longer exists)
        vm.expectRevert("ERC721: invalid token ID");
        lockNft.ownerOf(tokenId);
    }

    function test_DepositTokenToReceiver() public {
        address receiver = vm.createWallet("receiver").addr;
        uint256 depositAmount = _parseToken(75);

        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(depositAmount);
        lockNft.setApprovalForAll(address(vault), true);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, receiver, depositAmount, depositAmount);

        uint256 shares = vault.depositToken(tokenId, receiver);
        vm.stopPrank();

        assertEq(vault.balanceOf(receiver), shares);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_DepositTokenMultipleTimes() public {
        uint256 depositAmount1 = _parseToken(30);
        uint256 depositAmount2 = _parseToken(50);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(depositAmount1);
        uint256 tokenId2 = escrow.createLock(depositAmount2);
        lockNft.setApprovalForAll(address(vault), true);

        uint256 shares1 = vault.depositToken(tokenId1, alice);
        uint256 shares2 = vault.depositToken(tokenId2, alice);
        vm.stopPrank();

        assertEq(shares1, depositAmount1);
        assertEq(shares2, depositAmount2);
        assertEq(vault.balanceOf(alice), depositAmount1 + depositAmount2);
    }

    function test_DepositTokenFromMultipleUsers() public {
        uint256 aliceAmount = _parseToken(50);
        uint256 bobAmount = _parseToken(100);

        // Alice deposits token
        vm.startPrank(alice);
        uint256 aliceTokenId = escrow.createLock(aliceAmount);
        lockNft.setApprovalForAll(address(vault), true);
        uint256 aliceShares = vault.depositToken(aliceTokenId, alice);
        vm.stopPrank();

        // Bob deposits token
        vm.startPrank(bob);
        uint256 bobTokenId = escrow.createLock(bobAmount);
        lockNft.setApprovalForAll(address(vault), true);
        uint256 bobShares = vault.depositToken(bobTokenId, bob);
        vm.stopPrank();

        assertEq(aliceShares, aliceAmount);
        assertEq(bobShares, bobAmount);
        assertEq(vault.balanceOf(alice), aliceAmount);
        assertEq(vault.balanceOf(bob), bobAmount);
        assertEq(vault.totalAssets(), vault.totalSupply());
    }

    function test_DepositTokenMergesIntoMasterToken() public {
        uint256 depositAmount = _parseToken(50);
        uint256 masterTokenAmountBefore = escrow.locked(masterTokenId).amount;

        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(depositAmount);
        lockNft.setApprovalForAll(address(vault), true);
        vault.depositToken(tokenId, alice);
        vm.stopPrank();

        uint256 masterTokenAmountAfter = escrow.locked(masterTokenId).amount;

        assertEq(masterTokenAmountAfter, masterTokenAmountBefore + depositAmount);

        // Verify token was merged and no longer exists
        vm.expectRevert("ERC721: invalid token ID");
        lockNft.ownerOf(tokenId);
    }

    function test_DepositTokenAfterDonation() public {
        // Someone donates first
        _mintAndApprove(bob, address(vault), _parseToken(100));
        vm.prank(bob);
        vault.donate(_parseToken(100));

        uint256 shareValueBefore = vault.convertToAssets(1e18);

        // Alice deposits token
        uint256 depositAmount = _parseToken(50);
        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(depositAmount);
        lockNft.setApprovalForAll(address(vault), true);
        uint256 shares = vault.depositToken(tokenId, alice);
        vm.stopPrank();

        // Shares should be worth more than 1:1 due to donation
        uint256 shareValueAfter = vault.convertToAssets(1e18);
        assertEq(shareValueAfter, shareValueBefore);
        assertLt(shares, depositAmount); // Gets fewer shares due to increased share value
    }

    function test_DepositTokenPreviewDeposit() public {
        uint256 depositAmount = _parseToken(50);

        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(depositAmount);

        // Preview should match actual
        uint256 previewedShares = vault.previewDeposit(depositAmount);

        lockNft.setApprovalForAll(address(vault), true);
        uint256 actualShares = vault.depositToken(tokenId, alice);
        vm.stopPrank();

        assertEq(actualShares, previewedShares);
    }

    function testFuzz_DepositToken(uint256 amount) public {
        amount = bound(amount, escrow.minDeposit(), type(uint128).max);

        _mintAndApprove(alice, address(escrow), amount);

        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(amount);
        lockNft.setApprovalForAll(address(vault), true);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 shares = vault.depositToken(tokenId, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), totalAssetsBefore + amount);
    }
}
