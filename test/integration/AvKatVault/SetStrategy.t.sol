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
        address oldStrategy = address(vault.strategy());

        vm.expectEmit(true, true, true, true);
        emit Vault.StrategySet(newStrategy);

        vault.setStrategy(newStrategy);

        assertEq(address(vault.strategy()), newStrategy);
    }

    function test_SetStrategyToZeroAddress() public {
        vault.setStrategy(address(0));

        assertEq(address(vault.strategy()), address(0));
    }

    function test_SetStrategySameAddress() public {
        address currentStrategy = address(vault.strategy());

        vm.expectEmit(true, true, true, true);
        emit Vault.StrategySet(currentStrategy);

        vault.setStrategy(currentStrategy);

        assertEq(address(vault.strategy()), currentStrategy);
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

        // Verify vault state unchanged
        assertEq(address(vault.strategy()), newStrategy);
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }
}
