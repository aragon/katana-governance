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

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        selectors[2] = Handler.depositToken.selector;
        selectors[3] = Handler.donate.selector;
        selectors[4] = Handler.redeem.selector;
        FuzzSelector memory a = FuzzSelector(address(h), selectors);
        targetSelector(a);
    }

    function invariant_strategyOwnsMasterTokenOnly() public view {
        uint256 masterTokenId = autoCompoundStrategy.masterTokenId();
        address owner = vault.lockNft().ownerOf(masterTokenId);

        assertEq(owner, address(autoCompoundStrategy), "Strategy must always own master token");

        // Strategy should only hold the master token, no other NFTs
        uint256 strategyNftBalance = vault.lockNft().balanceOf(address(autoCompoundStrategy));
        assertEq(strategyNftBalance, 1, "Strategy should only hold master token NFT");
    }

    function invariant_vaultHoldsNoNFTs() public view {
        // Vault should not hold any NFTs (they are held by strategy)
        uint256 vaultNftBalance = vault.lockNft().balanceOf(address(vault));
        assertEq(vaultNftBalance, 0, "Vault should not hold any NFTs");
    }

    function invariant_strategyDelegation() public view {
        uint256 masterTokenId = autoCompoundStrategy.masterTokenId();
        address delegatee = autoCompoundStrategy.delegatee();

        if (delegatee == address(0)) {
            return;
        }

        // If delegatee is set, master token must be delegated to it
        assertTrue(ivotesAdapter.tokenIsDelegated(masterTokenId), "Master token must be delegated when delegatee is set");

        address actualDelegatee = ivotesAdapter.delegates(address(autoCompoundStrategy));
        assertEq(actualDelegatee, delegatee, "Strategy must delegate to configured delegatee");
    }

    // ==== ASSETS AND SHARES INVARIANTS ====

    function invariant_totalAssetsInEscrow() public view {
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 escrowLocked = escrow.locked(autoCompoundStrategy.masterTokenId()).amount;

        assertEq(vaultTotalAssets, escrowLocked, "Vault total assets must equal escrow locked amount");
    }

    function invariant_vaultHoldsNoAssets() public view {
        uint256 vaultBalance = MockERC20(vault.asset()).balanceOf(address(vault));
        assertEq(vaultBalance, 0, "Vault should not hold assets (all should be in escrow)");
    }

    function invariant_totalAssetsMatchesNetFlow() public view {
        uint256 totalDeposited = h.totalDeposited();
        uint256 totalWithdrawn = h.totalWithdrawn();
        uint256 totalDonated = h.totalDonated();
        uint256 currentAssets = vault.totalAssets();

        assertEq(
            totalDeposited + totalDonated - totalWithdrawn,
            currentAssets,
            "Deposits plus donations minus withdrawals must equal current assets"
        );
    }

    function invariant_conversionProportionality() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply > 0) {
            // For every share, convertToAssets should give proportional assets
            uint256 shareValue = vault.convertToAssets(1e18);
            uint256 expectedValue = (1e18 * totalAssets) / totalSupply;

            // Allow for rounding errors, especially with large donation amounts
            // Use relative tolerance: 1 wei per 1e18 of value
            uint256 tolerance = expectedValue > 1e18 ? expectedValue / 1e18 : 1;
            assertApproxEqAbs(shareValue, expectedValue, tolerance, "Share to asset conversion must be proportional");
        }

        if (totalAssets > 0) {
            // For every asset, convertToShares should give proportional shares
            uint256 assetShares = vault.convertToShares(1e18);
            uint256 expectedShares = (1e18 * totalSupply) / totalAssets;

            // Allow 1 wei tolerance for division rounding
            assertApproxEqAbs(assetShares, expectedShares, 1, "Asset to share conversion must be proportional");
        }
    }

    function invariant_sumOfSharesEqualsTotalSupply() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 sumOfActorShares = h.sumOfActorShares();
        uint256 address1Shares = vault.balanceOf(address(1));

        assertEq(sumOfActorShares + address1Shares, totalSupply, "Sum of all shares must equal total supply");
    }

    function invariant_address1InitialMint() public view {
        // address(1) should have shares equal to initial master token amount
        uint256 address1Balance = vault.balanceOf(address(1));

        // This should be > 0 after initializeMasterTokenId
        assertTrue(address1Balance > 0, "address(1) must have initial shares to prevent first depositor attack");
    }

    function invariant_donationsIncreaseShareValue() public view {
        uint256 totalDonated = h.totalDonated();

        if (totalDonated > 0) {
            // If donations occurred, totalAssets should be greater than totalSupply
            // (since initial ratio was 1:1 but donations add assets without shares)
            uint256 totalAssets = vault.totalAssets();
            uint256 totalSupply = vault.totalSupply();

            assertGt(totalAssets, totalSupply, "Donations should make totalAssets > totalSupply");
        }
    }
}
