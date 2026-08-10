// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../../Base.sol";

import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { Upgrades } from "@foundry-upgrades/src/LegacyUpgrades.sol";
import { Options } from "@foundry-upgrades/src/Options.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { AvKATVaultReference } from "test/upgrade/reference/AvKATVaultReference.sol";

contract VaultUpgradeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_UpgradeUnauthorized() public {
        address newImplementation = address(new AvKATVault());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(vault),
                address(alice),
                AvKATVault(newImplementation).VAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        vault.upgradeTo(newImplementation);
    }

    function test_UpgradeAuthorized() public {
        address newImplementation = address(new AvKATVault());

        // Upgrade should succeed
        vault.upgradeTo(address(newImplementation));

        assertEq(vault.implementation(), address(newImplementation));
    }

    /// @notice OZ Foundry Upgrades storage-layout + upgrade-safety check against the
    ///         frozen pre-conversion-window vault snapshot.
    function testValidateUpgrade() public {
        // Touch the type so Foundry emits the reference artifact for upgrades-core.
        assertTrue(type(AvKATVaultReference).creationCode.length > 0);

        Options memory options;

        string[] memory exclude = new string[](1);
        // disableInitializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        // Pre-existing patterns on AvKATVault (identical on the reference): constructor that only
        // calls `_disableInitializers()`, and `_pause()` without `__Pausable_init()`.
        options.unsafeAllow = "constructor,missing-initializer-call";

        options.referenceContract = "AvKATVaultReference.sol:AvKATVaultReference";
        Upgrades.validateUpgrade("AvKATVault.sol:AvKATVault", options);
    }
}
