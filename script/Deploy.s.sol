// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2 as console} from "forge-std/Script.sol";
// import {Forkable} from "src/utils/Forkable.sol";
// import {DAOHelper} from "src/utils/DAOHelper.sol";
// import {
//     TEST_SAFE_ADDRESS,
//     OSX_SEPOLIA_DAOFactory,
//     OSX_AVAX_C_DAOFactory,
//     OSX_AVAX_C_GlobalExecutor
// } from "src/utils/AragonState.sol";
// import {
//     IEcosystemComptroller,
//     IEcosystemUnitroller,
//     ISafe,
//     IMultiSend,
//     IMultiRewardDistributor
// } from "src/Interfaces.sol";
import {ProtocolFactoryBuilder, ProtocolFactory} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import {DAOFactory, PluginSetupRef, IPluginSetup, DAO, IDAO, PluginSetupProcessor} from "@aragon/osx/framework/dao/DAOFactory.sol";
// import {
//     StagedProposalProcessor as SPP
// } from "@aragon/staged-proposal-processor/StagedProposalProcessor.sol";

// import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
// import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
// import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
// import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

// import {Comptroller as BenqiComptroller} from "src/benqi/Comptroller.sol";
// import {Unitroller as BenqiUnitroller} from "src/benqi/Unitroller.sol";
// import {ProxyLib} from "src/utils/ProxyLib.sol";

// import "src/utils/Permissions.sol";

contract Deploy is Script {
    // using ProxyLib for address;

    address deployer;
    // DAOFactory daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
    // PluginRepo multisigRepo = PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO"));
    DAOFactory internal daoFactory;
    PluginRepo internal multisigRepo;

    modifier broadcast1() {
        // deployer = vm.addr(vm.envOr("PRIVATE_KEY", uint256(0xC0FFEE)));
        // vm.startBroadcast(deployer);
        // _;
        // vm.stopBroadcast();
        _;
    }

    function mainA() public {
        // Deploy OSX
        // Note that this will not be needed when osx is deployed on katana chain.
        ProtocolFactory factory = new ProtocolFactoryBuilder().build();
        factory.deployOnce();

        ProtocolFactory.Deployment memory deployment = factory.getDeployment();
        daoFactory = DAOFactory(deployment.daoFactory);
        multisigRepo = PluginRepo(deployment.multisigPluginRepo);

        // Deploy dao with multisig
        _deployDAOWithMultisig(getMultisigMembers());

        // Deploy ve...

    }

    function getDeploymentParameters() public returns (DeploymentParameters memory parameters) {
        address[] memory multisigMembers = readMultisigMembers();
        TokenParameters[] memory tokenParameters = getTokenParameters(mintTestTokens);

        // NOTE: Multisig is already deployed, using the existing Aragon's repo
        // NOTE: Deploying the plugin setup from the current script to avoid code size constraints

        GaugeVoterSetup gaugeVoterPluginSetup = deployGaugeVoterPluginSetup();

        parameters = DeploymentParameters({
            // Multisig settings
            minApprovals: vm.envUint("MIN_APPROVALS").toUint8(),
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: vm.envUint("FEE_PERCENT").toUint16(),
            cooldownPeriod: vm.envUint("COOLDOWN_PERIOD").toUint48(),
            minLockDuration: vm.envUint("MIN_LOCK_DURATION").toUint48(),
            votingPaused: vm.envBool("VOTING_PAUSED"),
            minDeposit: vm.envUint("MIN_DEPOSIT"),
            // Standard multisig repo
            multisigPluginRepo: PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS")),
            multisigPluginRelease: vm.envUint("MULTISIG_PLUGIN_RELEASE").toUint8(),
            multisigPluginBuild: vm.envUint("MULTISIG_PLUGIN_BUILD").toUint16(),
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: vm.envString("SIMPLE_GAUGE_VOTER_REPO_ENS_SUBDOMAIN"),
            // OSx addresses
            osxDaoFactory: vm.envAddress("DAO_FACTORY"),
            pluginSetupProcessor: PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR")),
            pluginRepoFactory: PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"))
        });
    }

    // function _deployDAOWithMultisig(
    //     address[] memory owners
    // ) internal returns (DAO, Multisig) {
    //     DAOFactory.DAOSettings memory settings = DAOFactory.DAOSettings({
    //         subdomain: "",
    //         metadata: bytes(""),
    //         daoURI: "",
    //         trustedForwarder: address(0)
    //     });

    //     // encode the multisig setup data
    //     DAOFactory.PluginSettings[]
    //         memory pluginSettings = defaultDaoFactoryMultisigPluginSettings(
    //             owners,
    //             1, // min approvals
    //             address(multisigRepo) // the multisig plugin repo address
    //         );

    //     // create the DAO with the multisig plugin
    //     (
    //         DAO dao,
    //         DAOFactory.InstalledPlugin[] memory installedPlugins
    //     ) = daoFactory.createDao(settings, pluginSettings);

    //     // instead the multisig should have execute permission and the deployer should be a member
    //     Multisig multisig = Multisig(installedPlugins[0].plugin);

    //     // roll +1 block for multisig to be ready
    //     vm.roll(block.number + 1);

    //     return (dao, multisig);
    // }

    // function defaultDaoFactoryMultisigPluginSettings(
    //     address[] memory _signers,
    //     uint8 _minApprovals,
    //     address _multisigPluginRepo
    // ) internal pure returns (DAOFactory.PluginSettings[] memory) {
    //     DAOFactory.PluginSettings[]
    //         memory pluginSettings = new DAOFactory.PluginSettings[](1);
    //     bytes memory multisigSetupData;
    //     {
    //         bytes memory pluginMetadata = bytes("Multisig Plugin Metadata");

    //         Multisig.MultisigSettings memory multisigSettings = Multisig
    //             .MultisigSettings({
    //                 onlyListed: true,
    //                 minApprovals: _minApprovals
    //             });

    //         IPlugin.TargetConfig memory targetConfig = IPlugin.TargetConfig({
    //             target: address(0), // Defaults to the DAO
    //             operation: IPlugin.Operation.Call
    //         });

    //         // encode it in the scope as we don't need the intermediate variables
    //         multisigSetupData = abi.encode(
    //             _signers,
    //             multisigSettings,
    //             targetConfig,
    //             pluginMetadata
    //         );
    //     }

    //     // deploy a 1.3 version of the multisig plugin
    //     // the protocol factory will have already deployed the multisig plugin repo
    //     pluginSettings[0] = DAOFactory.PluginSettings({
    //         pluginSetupRef: PluginSetupRef({
    //             versionTag: PluginRepo.Tag(1, 3),
    //             pluginSetupRepo: PluginRepo(_multisigPluginRepo)
    //         }),
    //         data: multisigSetupData
    //     });

    //     return pluginSettings;
    // }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFileName = "multisig-members.json";
        string memory path = string.concat(vm.projectRoot(), "/", membersFileName);
        string memory strJson = vm.readFile(path);
        
        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) {
            revert("The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME does not contain any members");
        }

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) {
            revert("The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME needs to contain at least one member");
        }
    }
}
