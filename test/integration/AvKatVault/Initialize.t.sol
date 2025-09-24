// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../Base.sol";

import { AvKATVault } from "src/AvKATVault.sol";

contract VaultInitializeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Initialize() public view {
        assertEq(vault.masterTokenId(), masterTokenId);
    }

    function testReverts_IfTokenNotOwned() public {
        _deployVault();

        token.approve(address(escrow), 1);
        uint256 wrongTokenId = escrow.createLock(1);
        vm.expectRevert(AvKATVault.TokenNotOwned.selector);
        vault.initializeMasterTokenId(wrongTokenId);
    }

    function test_CanOnlyBeCalledOnce() public {
        vm.expectRevert();
        vault.initializeMasterTokenId(masterTokenId);
    }
}
