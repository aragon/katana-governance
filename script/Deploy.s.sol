// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Script, console2 as console } from "forge-std/Script.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    DAOFactory,
    PluginSetupRef,
    IPluginSetup,
    DAO,
    PluginSetupProcessor
} from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";
import { Multisig } from "@aragon/multisig-plugin/Multisig.sol";
import { IPlugin } from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import { PermissionLib } from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { GaugeVoterSetupV1_4_0 as GaugeVoterSetup } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import {
    GaugesDaoFactoryV1_4_0 as VeGovernanceFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters
} from "@factory/GaugesDaoFactory_v1_4_0.sol";

import { VKatMetadata } from "src/VKatMetadata.sol";
import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";

import { AutoCompoundStrategy } from "src/AutoCompoundStrategy.sol";
import { Swapper } from "src/Swapper.sol";
import { AvKATVault } from "src/AvKATVault.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";
import { deployVault, deploySwapper, deployAutoCompoundStrategy, deployVKatMetadata } from "src/utils/Deployers.sol";

contract Deploy is Script {
    using ProxyLib for address;
    using SafeCast for uint256;

    address deployer;
    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
    address merkleDistributor = vm.envAddress("MERKLE_DISTRIBUTOR");
    address executor = vm.envAddress("EXECUTOR");

    function run() public {
        deployer = vm.addr(deployerPrivateKey);
        vm.createSelectFork(vm.rpcUrl(vm.envString("RPC")));

        vm.startBroadcast(deployerPrivateKey);

        DeploymentParameters memory params = getDeploymentParameters();

        // ======== Deploys a dao + all the architecture of ve-governance ========
        VeGovernanceFactory factory = new VeGovernanceFactory(params);
        factory.deployOnce();

        DeploymentParameters memory deploymentParameters = factory.getDeploymentParameters();
        Deployment memory deployment = factory.getDeployment();

        VotingEscrow escrow = deployment.gaugeVoterPluginSets[0].votingEscrow;

        // ======== Deploys Vkat Related contracts ========

        // deploy vault...
        (, address vault) = deployVault(
            address(deployment.dao),
            address(escrow),
            address(0),
            address(escrow.token()),
            "Autocompounding veKAT",
            "avKAT"
        );

        // deploy swapper
        address swapper = deploySwapper(merkleDistributor, address(escrow), executor);

        // deploy vkatmetadata
        (, address vkatMetadata) = deployVKatMetadata(
            address(deployment.dao),
            escrow.lockNFT(),
            new address[](0),
            IVKatMetadata.VKatMetaDataV1(new uint16[](0), new address[](0))
        );

        // deploy compound strategy
        (, address autoCompoundStrategy) =
            deployAutoCompoundStrategy(address(deployment.dao), address(escrow), swapper, vault, merkleDistributor);

        Action[] memory actions = getActions(
            address(deployment.dao), vkatMetadata, autoCompoundStrategy, vault, address(deployment.multisigPlugin)
        );

        Multisig multisig = Multisig(address(deployment.multisigPlugin));
        multisig.createProposal(
            bytes("initial proposal"), actions, 0, true, true, uint64(block.timestamp), uint64(block.timestamp + 7 days)
        );

        printDeploymentSummary(address(factory), deployment, deploymentParameters);

        vm.stopBroadcast();
    }

    function getActions(
        address _dao,
        address _vkatMetadata,
        address _compoundStrategy,
        address _avKatVault,
        address _multisig
    )
        internal
        view
        returns (Action[] memory actions)
    {
        Action[] memory actions = new Action[](3);

        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](4);

        // VKatMetadata permissions
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _vkatMetadata,
            who: _dao,
            permissionId: VKatMetadata(_vkatMetadata).ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // compound strategy permissions
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _compoundStrategy,
            who: _dao,
            permissionId: AutoCompoundStrategy(_compoundStrategy).AUTOCOMPOUND_STRATEGY_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // vault permissions
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _avKatVault,
            who: _dao,
            permissionId: AvKATVault(_avKatVault).VAULT_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _avKatVault,
            who: _dao,
            permissionId: AvKATVault(_avKatVault).SWEEPER_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        actions[0].to = _dao;
        actions[0].data = abi.encodeCall(PermissionManager.applyMultiTargetPermissions, permissions);

        actions[1].to = _avKatVault;
        actions[1].data = abi.encodeCall(AvKATVault.setStrategy, _compoundStrategy);

        address[] memory addrs = new address[](1);
        addrs[0] = address(this);
        actions[2].to = _multisig;
        actions[2].data = abi.encodeCall(Multisig.removeAddresses, (addrs));

        return actions;
    }

    function getDeploymentParameters() public returns (DeploymentParameters memory parameters) {
        TokenParameters[] memory tokenParameters = getTokenParameters(vm.envOr("MINT_TEST_TOKENS", false));
        GaugeVoterSetup gaugeVoterPluginSetup = deployGaugeVoterPluginSetup();

        parameters = DeploymentParameters({
            // Multisig settings
            minApprovals: vm.envUint("MIN_APPROVALS").toUint8(),
            multisigMembers: readMultisigMembers(),
            multisigMetadata: bytes(vm.envString("MULTISIG_METADATA_URI")),
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

    function deployGaugeVoterPluginSetup() internal returns (GaugeVoterSetup result) {
        int256[3] memory coefficients;
        coefficients[0] = vm.envUint("CONSTANT_COEFFICIENT").toInt256();
        coefficients[1] = vm.envUint("LINEAR_COEFFICIENT").toInt256();
        coefficients[2] = 0;

        uint256 maxEpoch = vm.envUint("MAX_EPOCHS");

        result = new GaugeVoterSetup(
            address(new AddressGaugeVoter()),
            address(new Curve(coefficients, maxEpoch)),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock()),
            address(new EscrowIVotesAdapter())
        );
    }

    function readMultisigMembers() public view returns (address[] memory) {
        // JSON list of members
        string memory membersFileName = "multisig-members.json";
        string memory path = string.concat(vm.projectRoot(), "/", membersFileName);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) {
            revert("The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME does not contain any members");
        }

        address[] memory result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) {
            revert("The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME needs to contain at least one member");
        }

        address[] memory resultWithAddressThis = new address[](result.length + 1);
        for (uint256 i = 0; i < result.length; i++) {
            resultWithAddressThis[i] = result[i];
        }

        resultWithAddressThis[resultWithAddressThis.length - 1] = address(this);

        return resultWithAddressThis;
    }

    function getTokenParameters(bool mintTestTokens) internal returns (TokenParameters[] memory tokenParameters) {
        if (mintTestTokens) {
            // MINT
            console.log("Deploying 2 token contracts (testing)");

            address[] memory multisigMembers = readMultisigMembers();
            tokenParameters = new TokenParameters[](1);
            tokenParameters[0] = TokenParameters({
                token: createTestToken(multisigMembers),
                veTokenName: "VE Token 1",
                veTokenSymbol: "veTK1"
            });
        } else {
            // USE TOKEN(s)
            bool hasTwoTokens = vm.envAddress("TOKEN2_ADDRESS") != address(0);
            tokenParameters = new TokenParameters[](hasTwoTokens ? 2 : 1);

            console.log("Using token", vm.envAddress("TOKEN1_ADDRESS"));
            tokenParameters[0] = TokenParameters({
                token: vm.envAddress("TOKEN1_ADDRESS"),
                veTokenName: vm.envString("VE_TOKEN1_NAME"),
                veTokenSymbol: vm.envString("VE_TOKEN1_SYMBOL")
            });

            if (hasTwoTokens) {
                console.log("Using token", vm.envAddress("TOKEN2_ADDRESS"));
                tokenParameters[1] = TokenParameters({
                    token: vm.envAddress("TOKEN2_ADDRESS"),
                    veTokenName: vm.envString("VE_TOKEN2_NAME"),
                    veTokenSymbol: vm.envString("VE_TOKEN2_SYMBOL")
                });
            }
        }
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint256 i = 0; i < holders.length;) {
            newToken.mint(holders[i], 5000 ether);

            unchecked {
                i++;
            }
        }

        return address(newToken);
    }

    function printDeploymentSummary(
        address _veFactory,
        Deployment memory _veDeployment,
        DeploymentParameters memory _veDeploymentParams
    )
        internal
        view
    {
        console.log("");
        console.log("Deployed from: ", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Factory:", address(_veFactory));
        console.log("");
        console.log("DAO:", address(_veDeployment.dao));
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(_veDeployment.multisigPlugin));
        console.log("");

        for (uint256 i = 0; i < _veDeployment.gaugeVoterPluginSets.length;) {
            console.log("- Using token:", address(_veDeploymentParams.tokenParameters[i].token));
            console.log("  Gauge voter plugin:", address(_veDeployment.gaugeVoterPluginSets[i].plugin));
            console.log("  Curve:", address(_veDeployment.gaugeVoterPluginSets[i].curve));
            console.log("  Exit Queue:", address(_veDeployment.gaugeVoterPluginSets[i].exitQueue));
            console.log("  Voting Escrow:", address(_veDeployment.gaugeVoterPluginSets[i].votingEscrow));
            console.log("  Clock:", address(_veDeployment.gaugeVoterPluginSets[i].clock));
            console.log("  NFT Lock:", address(_veDeployment.gaugeVoterPluginSets[i].nftLock));
            console.log("  Escrow IVotes Adapter:", address(_veDeployment.gaugeVoterPluginSets[i].delegationAdapter));
            console.log("");

            unchecked {
                i++;
            }
        }

        console.log("Plugin repositories");
        console.log("- Multisig plugin repository (existing):", address(_veDeploymentParams.multisigPluginRepo));
        console.log("- Gauge voter plugin repository:", address(_veDeployment.gaugeVoterPluginRepo));
    }
}
