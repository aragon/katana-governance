pragma solidity ^0.8.17;

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { Base } from "../Base.sol";
import { AvKatVaultHandler as Handler } from "./handlers/AvKatVaultHandler.sol";

import { AvKATVault } from "src/AvKATVault.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract VaultInvariant is StdInvariant, Base {
    Handler internal h;

    function setUp() public override {
        super.setUp();

        h = new Handler(vault);

        targetContract(address(h));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        FuzzSelector memory a = FuzzSelector(address(h), selectors);
        targetSelector(a);
    }

    function invariant_totalAssetsInEscrow() public view {
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 escrowLocked = escrow.locked(vault.masterTokenId()).amount;

        assertEq(vaultTotalAssets, escrowLocked, "Vault total assets must equal escrow locked amount");
    }

    function invariant_vaultHoldsNoAssets() public view {
        assertEq(
            MockERC20(vault.asset()).balanceOf(address(vault)),
            0,
            "Vault should not hold assets (all should be in escrow)"
        );
    }

    function invariant_depositWithdrawSymmetry() public view {
        uint256 totalDeposited = h.totalDeposited();
        uint256 totalWithdrawn = h.totalWithdrawn();
        uint256 currentAssets = vault.totalAssets();

        assertEq(totalDeposited - totalWithdrawn, currentAssets, "Deposits minus withdrawals must equal current assets");
    }
}
