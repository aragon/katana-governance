// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2 as console} from "forge-std/Script.sol";
import {Forkable} from "src/utils/Forkable.sol";
import {DAOHelper} from "src/utils/DAOHelper.sol";
import {
    TEST_SAFE_ADDRESS,
    OSX_SEPOLIA_DAOFactory,
    OSX_AVAX_C_DAOFactory,
    OSX_AVAX_C_GlobalExecutor
} from "src/utils/AragonState.sol";
import {
    IEcosystemComptroller,
    IEcosystemUnitroller,
    ISafe,
    IMultiSend,
    IMultiRewardDistributor
} from "src/Interfaces.sol";
import {
    ProtocolFactoryBuilder,
    ProtocolFactory
} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import {
    DAOFactory,
    PluginSetupRef,
    IPluginSetup,
    DAO,
    IDAO,
    PluginSetupProcessor
} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {
    StagedProposalProcessor as SPP
} from "@aragon/staged-proposal-processor/StagedProposalProcessor.sol";

import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {Comptroller as BenqiComptroller} from "src/benqi/Comptroller.sol";
import {Unitroller as BenqiUnitroller} from "src/benqi/Unitroller.sol";
import {ProxyLib} from "src/utils/ProxyLib.sol";

import "src/utils/Permissions.sol";

contract DeployDAOConnectedToExistingSafeAndComptroller is Forkable, DAOHelper {
    using ProxyLib for address;

    address deployer;
    DAOFactory daoFactory = DAOFactory(OSX_AVAX_C_DAOFactory);

    modifier broadcast() {
        deployer = vm.addr(vm.envOr("PRIVATE_KEY", uint256(0xC0FFEE)));
        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function run() public avalancheMainnetForkLatest broadcast {
       

    }
}