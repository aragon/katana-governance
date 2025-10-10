// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../../Base.sol";

import { deployVault } from "src/utils/Deployers.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVaultNFT as IVault } from "src/interfaces/IVaultNFT.sol";

contract VaultInitializeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Initialize() public view {
        assertEq(address(vault.strategy()), address(acStrategy));
        assertEq(vault.masterTokenId(), masterTokenId);
    }

    function testReverts_IfTokenNotApprovedOrOwned() public {
        (, address newVault) = deployVault(address(dao), address(escrow), "name", "symbol");

        // Create a token but don't transfer it to the vault
        escrowToken.approve(address(escrow), 1);
        uint256 wrongTokenId = escrow.createLock(1);

        vm.expectRevert();
        Vault(newVault).initializeMasterTokenAndStrategy(wrongTokenId, address(acStrategy));
    }

    function test_CanOnlyBeCalledOnce() public {
        vm.expectRevert(IVault.MasterTokenAlreadySet.selector);
        vault.initializeMasterTokenAndStrategy(masterTokenId, address(acStrategy));
    }

    function testReverts_IfTokenIdCannotBeZero() public {
        (, address newVault) = deployVault(address(dao), address(escrow), "name", "symbol");

        vm.expectRevert(IVault.TokenIdCannotBeZero.selector);
        Vault(newVault).initializeMasterTokenAndStrategy(0, address(acStrategy));
    }
}
