// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVotingEscrowCoreErrors } from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";
import { Script, console2 as console } from "forge-std/Script.sol";

contract VaultDonateTest is Base {
    using ProxyLib for address;

    event Donation(address indexed donor, uint256 amount);

    function setUp() public override {
        super.setUp();

        _mintAndApprove(alice, address(vault), _parseToken(1000));
        _mintAndApprove(bob, address(vault), _parseToken(1000));
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

        vm.expectRevert(Vault.StrategyNotSet.selector);
        newVault.donate(_parseToken(100));
        vm.stopPrank();
    }

    function testRevert_IfZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        vault.donate(0);
    }

    function testRevert_IfInsufficientAllowance() public {
        vm.startPrank(alice);
        escrowToken.approve(address(vault), _parseToken(50) - 1);

        vm.expectRevert();
        vault.donate(_parseToken(50));
        vm.stopPrank();
    }

    function test_DonateIncreasesTotalAssetsWithoutMintingShares() public {
        uint256 donateAmount = _parseToken(100);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vault.donate(donateAmount);

        // Total assets should increase
        assertEq(vault.totalAssets(), totalAssetsBefore + donateAmount, "Total assets should increase");

        // Total supply should remain the same (no shares minted)
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should not change");

        // Alice's shares should remain the same
        assertEq(vault.balanceOf(alice), aliceSharesBefore, "Alice's shares should not change");
    }

    function test_DonateIncreasesShareValue() public {
        // First, alice deposits to get shares
        uint256 depositAmount = _parseToken(100);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        uint256 shareValueBefore = vault.convertToAssets(1e18);

        // Bob donates
        uint256 donateAmount = _parseToken(50);
        vm.prank(bob);
        vault.donate(donateAmount);

        uint256 shareValueAfter = vault.convertToAssets(1e18);

        // Share value should increase
        assertGt(shareValueAfter, shareValueBefore, "Share value should increase after donation");

        // Alice's shares are now worth more
        uint256 aliceAssetsAfter = vault.convertToAssets(aliceShares);
        assertGt(aliceAssetsAfter, depositAmount, "Alice's shares should be worth more than initial deposit");
    }

    function test_DonateWithMultipleShareholdersBenefitsAll() public {
        // Alice and Bob deposit equal amounts
        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        vm.prank(bob);
        vault.deposit(_parseToken(100), bob);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 bobSharesBefore = vault.balanceOf(bob);

        uint256 aliceValueBefore = vault.convertToAssets(aliceSharesBefore);
        uint256 bobValueBefore = vault.convertToAssets(bobSharesBefore);

        // Charlie donates
        address charlie = vm.createWallet("charlie").addr;
        _mintAndApprove(charlie, address(vault), _parseToken(100));

        vm.prank(charlie);
        vault.donate(_parseToken(100));

        // Both alice and bob benefit proportionally
        uint256 aliceValueAfter = vault.convertToAssets(aliceSharesBefore);
        uint256 bobValueAfter = vault.convertToAssets(bobSharesBefore);

        assertGt(aliceValueAfter, aliceValueBefore, "Alice's share value should increase");
        assertGt(bobValueAfter, bobValueBefore, "Bob's share value should increase");

        // They should benefit equally (since they had equal shares)
        assertEq(aliceValueAfter - aliceValueBefore, bobValueAfter - bobValueBefore, "Benefit should be proportional");
    }

    function test_DonateTransfersTokensFromDonor() public {
        uint256 donateAmount = _parseToken(100);
        uint256 aliceBalanceBefore = escrowToken.balanceOf(alice);

        vm.prank(alice);
        vault.donate(donateAmount);

        assertEq(
            escrowToken.balanceOf(alice), aliceBalanceBefore - donateAmount, "Tokens should be transferred from donor"
        );
    }

    function test_DonateMergesIntoMasterToken() public {
        uint256 donateAmount = _parseToken(100);
        uint256 masterTokenAmountBefore = escrow.locked(masterTokenId).amount;

        vm.prank(alice);
        vault.donate(donateAmount);

        uint256 masterTokenAmountAfter = escrow.locked(masterTokenId).amount;

        assertEq(
            masterTokenAmountAfter,
            masterTokenAmountBefore + donateAmount,
            "Master token amount should increase by donation amount"
        );
    }

    function test_DonateDoesNotAffectVaultTokenBalance() public {
        uint256 donateAmount = _parseToken(100);

        vm.prank(alice);
        vault.donate(donateAmount);

        // Vault should not hold any raw tokens (all in escrow)
        assertEq(escrowToken.balanceOf(address(vault)), 0, "Vault should not hold tokens after donation");
    }

    function test_MultipleDonationsCompound() public {
        // Alice deposits to get shares
        vm.prank(alice);
        vault.deposit(_parseToken(100), alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Bob donates twice
        vm.startPrank(bob);
        vault.donate(_parseToken(50));
        vault.donate(_parseToken(30));
        vm.stopPrank();

        assertEq(vault.totalAssets(), totalAssetsBefore + _parseToken(80), "Total assets should increase by sum");
        assertEq(vault.totalSupply(), totalSupplyBefore, "Total supply should remain unchanged");
    }

    function testFuzz_DonateAlwaysIncreasesShareValue(uint256 depositAmount, uint256 donateAmount) public {
        depositAmount = bound(depositAmount, escrow.minDeposit(), type(uint128).max);
        donateAmount = bound(donateAmount, escrow.minDeposit(), type(uint128).max);
        _mintAndApprove(alice, address(vault), depositAmount);
        _mintAndApprove(bob, address(vault), donateAmount);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Bob donates
        vm.prank(bob);
        vault.donate(donateAmount);

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // Total assets should increase by donation amount
        assertEq(totalAssetsAfter, totalAssetsBefore + donateAmount, "Total assets should increase by donation");

        // Total supply should remain unchanged
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged");

        // Since totalAssets increased and totalSupply stayed the same, share value must increase
        // (though it may not be observable due to rounding when checking convertToAssets(1e18))
    }

    // TODO: add...
    function test_VaultResistsDonationInflationAttack() public {
        uint256 initialTotalAssets = escrow.locked(masterTokenId).amount;
        uint256 initialTotalSupply = vault.totalSupply();

        console.log("init: totalAssets and totalShares", initialTotalAssets, initialTotalSupply);

        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");

        // Attack parameters
        uint256 attackerDeposit = escrow.minDeposit(); // Smallest allowed deposit
        uint256 donationAmount = _parseToken(100); // Large donation to inflate
        uint256 victimDeposit = _parseToken(50); // Victim's intended deposit

        _mintAndApprove(attacker, address(vault), attackerDeposit + donationAmount);
        _mintAndApprove(victim, address(vault), victimDeposit);

        // Step 1: Attacker deposits minimum amount to get initial shares
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(attackerDeposit, attacker);
        // assertEq(attackerShares, attackerDeposit, "Initial deposit should be 1:1");

        console.log(
            "after attacker deposits minDeposit, totalAssets and totalShares", vault.totalAssets(), vault.totalSupply()
        );

        // Step 2: Attacker donates to inflate the share price
        vm.prank(attacker);
        vault.donate(donationAmount);
        // 49 999 777 777 283 949 520
        // 47 727 272 727 272 727 273
        // 34 090 909 090 909 090 909
        // 100000 000 000 000 000 002
        console.log("attacker donates, totalAssets and totalShares: ", vault.totalAssets(), vault.totalSupply());
        // Now totalAssets = attackerDeposit + donationAmount
        // but totalSupply = attackerShares (only)
        uint256 inflatedAssets = vault.totalAssets();
        uint256 totalShares = vault.totalSupply();

        // assertEq(inflatedAssets, initialAmount + attackerDeposit + donationAmount, "Assets should be inflated");
        // assertEq(totalShares, initialSupply + attackerShares);

        // Calculate share price after inflation
        // uint256 pricePerShare = (inflatedAssets * 1e18) / totalShares;

        // Step 3: Victim tries to deposit
        vm.prank(victim);
        uint256 victimShares = vault.deposit(victimDeposit, victim);

        // In vulnerable vault: victimShares = (victimDeposit * totalShares) / inflatedAssets
        // If victimDeposit < inflatedAssets/totalShares, victimShares rounds to 0

        console.log("victim deposits, totalAssets and totalShares: ", vault.totalAssets(), vault.totalSupply());

        console.log("attacker shares: ", vault.balanceOf(attacker));
        console.log("victim shares: ", vault.balanceOf(victim));

        console.log("attacker gets", vault.convertToAssets(vault.balanceOf(attacker)));

        console.log("victim gets", vault.convertToAssets(vault.balanceOf(victim)));

        // if (victimShares == 0) {
        //     // Attack succeeded - victim lost everything
        //     fail("VULNERABLE: Victim received 0 shares and lost their deposit!");
        // }

        // // // Verify victim got reasonable shares for their deposit
        // // assertGt(victimShares, 0, "Victim should receive shares");

        // // // Verify victim can withdraw close to what they deposited
        // // uint256 victimCanWithdraw = vault.convertToAssets(victimShares);
        // console.log("donationAmount", donationAmount);
        // console.log("victimDepositt", victimDeposit);
        // console.log("totalSupply", vault.totalSupply());
        // console.log("totalShares", vault.totalAssets());

        // console.log("fuckyeah ", victimDeposit, victimShares, victimCanWithdraw);

        // console.log(
        //     "omg 123", vault.convertToAssets(vault.balanceOf(attacker)),
        // vault.convertToAssets(vault.balanceOf(victim))
        // );

        // console.log(vault.totalAssets(), vault.totalSupply());

        // vault starts with: 1 assets and 1 shares
        // attacker donates 100000000000000000000
        // victimDeposit: 50000000000000000000

        // victimDeposit: 37500000000000000000

        // assertGe(victimCanWithdraw, (victimDeposit * 95) / 100, "Victim should be able to withdraw most of deposit");

        // // Verify attacker can't steal victim's funds
        // uint256 attackerCanWithdraw = vault.convertToAssets(attackerShares);
        // uint256 attackerProfit = attackerCanWithdraw > (attackerDeposit + donationAmount)
        //     ? attackerCanWithdraw - (attackerDeposit + donationAmount)
        //     : 0;

        // assertLt(attackerProfit, victimDeposit / 10, "Attacker shouldn't profit significantly from victim");
    }
}

// 50000000000000000000
// 37500000000000000000
// 37500000000000000000
// 100000000000000000000

// 1. Initial state: Vault starts with masterToken (let's say 1 wei for simplicity)
// totalAssets = 1
// totalSupply = 1

// 2. Attacker deposits 1 wei:
// totalAssets = 2
// totalSupply = 2
// Attacker gets 1 share

// 3. Attacker donates 100e18:
// totalAssets = 2 + 100e18 = 100000000000000000002
// totalSupply = 2 (unchanged, donation doesn't mint shares)
// Price per share = 100000000000000000002 / 2 = ~50e18 per share

// 4. Victim deposits 50e18:
// Shares calculation: shares = (50e18 * (2 + 1)) / (100000000000000000002 + 1) = 1.5 = 1
// shares = 1
// totalAssets = 150000000000000000002
// totalSupply = 3

// function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view virtual returns (uint256)
// {
//     return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
// }

// (1 * (150000000000000000002 + 1)) / (3 + 1)
