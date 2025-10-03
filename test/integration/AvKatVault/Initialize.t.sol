// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../../Base.sol";

import { AutoCompoundStrategy } from "src/AutoCompoundStrategy.sol";

contract VaultInitializeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    // TODO: GIORGI add more tests

    function test_CanOnlyBeCalledOnce() public {
        vm.expectRevert(AutoCompoundStrategy.MasterTokenAlreadySet.selector);
        // autoCompoundStrategy.initializeMasterTokenId(masterTokenId);
    }
}
