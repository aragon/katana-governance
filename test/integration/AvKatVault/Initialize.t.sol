// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { console2 as console } from "forge-std/console2.sol";

contract VaultInitializeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Initialize() public {
        assertEq(vault.masterTokenId(), masterTokenId);
    }

    function testReverts_IfTokenNotOwned() public {
        _deployVault();

        token.approve(address(escrow), 1);
        uint256 wrongTokenId = escrow.createLock(1);
        vm.expectRevert(AvKATVault.TokenNotOwned.selector);
        vault.initialize(wrongTokenId);
    }

    function test_CanOnlyBeCalledOnce() public {
        vm.expectRevert();
        vault.initialize(masterTokenId);
    }
}
