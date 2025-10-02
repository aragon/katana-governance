// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { Base } from "../../Base.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";

contract VaultSetStrategyTest is Base {
    address internal newStrategy = vm.createWallet("newStrategy").addr;

    function setUp() public override {
        super.setUp();
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

    function test_SetStrategy() public {
        address oldStrategy = vault.strategy();

        vm.expectEmit(true, true, true, true);
        emit Vault.StrategySet(newStrategy);

        vault.setStrategy(newStrategy);

        assertEq(vault.strategy(), newStrategy);
    }

    function test_UpdatesDelegateeToNewStrategy() public {
        // Check initial delegation
        address initialStrategy = vault.strategy();
        address delegatee = ivotesAdapter.delegates(address(vault));
        assertEq(delegatee, initialStrategy);

        // Set new strategy
        vault.setStrategy(newStrategy);

        // Check delegation changed to new strategy
        delegatee = ivotesAdapter.delegates(address(vault));
        assertEq(delegatee, newStrategy);
    }

    function test_SetStrategyToZeroAddress() public {
        vault.setStrategy(address(0));

        assertEq(vault.strategy(), address(0));
        assertEq(ivotesAdapter.delegates(address(vault)), address(0));
    }

    function test_SetStrategySameAddress() public {
        address currentStrategy = vault.strategy();

        vm.expectEmit(true, true, true, true);
        emit Vault.StrategySet(currentStrategy);

        vault.setStrategy(currentStrategy);

        assertEq(vault.strategy(), currentStrategy);
    }

    function test_SetStrategyAfterDeposit() public {
        uint256 amount = _parseToken(100);
        _mintAndApprove(alice, address(vault), amount);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 totalAssetsBefore = vault.totalAssets();

        // Change strategy
        vault.setStrategy(newStrategy);

        // Verify delegation changed but vault state unchanged
        assertEq(vault.strategy(), newStrategy);
        assertEq(ivotesAdapter.delegates(address(vault)), newStrategy);
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }
}
