// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { AutoCompoundStrategy } from "src/strategies/AutoCompoundStrategy.sol";
import { deployAutoCompoundStrategy } from "src/utils/Deployers.sol";

contract VaultSetStrategyTest is Base {
    address internal newStrategy;

    function setUp() public override {
        super.setUp();

        (, address newStrategy_) = deployAutoCompoundStrategy(
            address(dao), address(escrow), address(swapper), address(vault), address(merklDistributor)
        );
        newStrategy = newStrategy_;
    }

    function testRevert_IfCallerNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(vault), alice, vault.VAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        vault.setStrategy(newStrategy);
    }

    function test_SetsStrategy() public {
        vm.expectEmit(true, true, true, true);
        emit Vault.StrategySet(newStrategy);

        vault.setStrategy(newStrategy);

        assertEq(address(vault.strategy()), newStrategy);
    }

    function test_SetStrategyToZeroAddress() public {
        vault.setStrategy(address(0));

        assertEq(address(vault.strategy()), address(0));
    }

    function testRevert_IfSetSameStrategy() public {
        vm.expectRevert(Vault.SameStrategyNotAllowed.selector);
        vault.setStrategy(address(acStrategy));
    }

    function test_SetStrategyAfterDeposit() public {
        uint256 amount = _parseToken(100);
        _mintAndApprove(alice, address(vault), amount);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();
        address oldStrategy = address(vault.strategy());

        // Verify old strategy owns the master token before
        assertEq(lockNft.ownerOf(masterTokenId), oldStrategy);

        // Change strategy
        vault.setStrategy(newStrategy);

        // Verify vault state
        assertEq(address(vault.strategy()), newStrategy);
        assertEq(vault.totalAssets(), totalAssetsBefore);

        // Verify master token was transferred to new strategy
        assertEq(lockNft.ownerOf(masterTokenId), newStrategy);

        // Verify new strategy has the correct master token ID
        assertEq(IStrategy(newStrategy).totalAssets(), totalAssetsBefore);
    }
}
