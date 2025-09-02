// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "./Base.sol";
import { AvKATVault } from "../src/AvKATVault.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";
import { console2 as console } from "forge-std/console2.sol";

contract VaultTest is Base {
    AvKATVault public vault;

    function setUp() public override {
        super.setUp();

        vault = new AvKATVault(
            address(dao), address(escrowIVotesAdapter), address(0), address(0), "Autocompounding veKAT", "avKAT"
        );

        _createProposal(
            address(dao),
            abi.encodeCall(PermissionManager.grant, (address(vault), address(this), vault.VAULT_ADMIN_ROLE()))
        );
        _createProposal(
            address(dao), abi.encodeCall(PermissionManager.grant, (address(vault), address(this), vault.SWEEPER_ROLE()))
        );
    }

    function test_one() public { }
}
