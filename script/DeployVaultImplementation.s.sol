// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Script, console2 as console } from "forge-std/Script.sol";

import { AvKATVault } from "src/AvKATVault.sol";

/// @notice Deploys a new `AvKATVault` implementation. The proxy is not touched here: `_authorizeUpgrade`
///         is gated by `VAULT_ADMIN_ROLE`, which the DAO holds, so `upgradeTo(newImplementation)` has to
///         be proposed on the vault proxy through the DAO multisig.
contract DeployVaultImplementation is Script {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        address newImplementation = address(new AvKATVault());

        vm.stopBroadcast();

        console.log("New AvKATVault implementation:", newImplementation);
        console.log("Propose `upgradeTo` with this address on the vault proxy from the DAO multisig.");
    }
}
