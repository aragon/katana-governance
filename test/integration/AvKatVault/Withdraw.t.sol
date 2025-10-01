// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";

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
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // before amounts
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 assetsBefore = escrowToken.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);

        // Alice withdraws 50
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(alice, alice, alice, withdrawAmount, withdrawAmount);

        vm.prank(alice);
        uint256 sharesAfter = vault.withdraw(withdrawAmount, alice, alice);

        // after amounts
        assertEq(sharesAfter, _parseToken(50));
        assertEq(vault.balanceOf(alice), sharesBefore - sharesAfter);
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount);
        assertEq(escrow.locked(masterTokenId).amount, totalAssetsBefore - withdrawAmount);
    }

    function test_withdrawsToReceiver() public {
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

        // alice withdraws and specifies `receiver` as recipient.
        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmount, receiver, alice);

        assertEq(shares, _parseToken(50));
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
        vault.approve(bob, depositAmount);
        vm.stopPrank();

        // bob withdraws on behalf of alice
        vm.prank(bob);
        uint256 shares = vault.withdraw(withdrawAmount, bob, alice);

        assertEq(shares, _parseToken(50));
        uint256 remaining = depositAmount - withdrawAmount;
        assertEq(vault.balanceOf(alice), remaining);
        assertEq(vault.allowance(alice, bob), remaining);
    }

    // ================== Recover NFT ==================
    function testRevert_IfRecoversAlreadyDeposittedToken() public {
        vm.startPrank(alice);
        uint256 tokenId = escrow.createLock(_parseToken(50));
        lockNft.setApprovalForAll(address(vault), true);
        vault.depositToken(tokenId, alice);
        vm.stopPrank();

        vm.expectRevert("ERC721: invalid token ID");
        vault.recoverNFT(tokenId, address(this));
    }

    function testRevert_IfRecoversMasterTokenId() public {
        vm.expectRevert(Vault.CannotTransferMasterToken.selector);
        vault.recoverNFT(masterTokenId, address(this));
    }

    function test_RecoversMistakenlyTransferedNFT() public {
        vm.prank(alice);
        uint256 tokenId = escrow.createLockFor(_parseToken(50), address(this));

        // send nft by mistake
        lockNft.transferFrom(address(this), address(vault), tokenId);

        // recover
        vault.recoverNFT(tokenId, address(this));
        assertEq(lockNft.ownerOf(tokenId), address(this));
    }
}
