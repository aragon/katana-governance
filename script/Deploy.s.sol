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
import { Multisig } from "@aragon/multisig-plugin/Multisig.sol";

import { IPlugin } from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import { GaugeVoterSetupV1_4_0 as GaugeVoterSetup } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
// import { VeFactory, DeploymentParameters, Deployment, TokenParameters } from "../src/VeFactory.sol";
import {
    GaugesDaoFactoryV1_4_0 as VeGovernanceFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters
} from "@factory/GaugesDaoFactory_v1_4_0.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract Deploy is Script {
    // using ProxyLib for address;
    using SafeCast for uint256;

    address deployer;
    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");

    function run() public {
        deployer = vm.addr(deployerPrivateKey);
        vm.createSelectFork(vm.rpcUrl(vm.envString("RPC")));

        vm.startBroadcast(deployerPrivateKey);

        DeploymentParameters memory params = getDeploymentParameters();

        // Deploys a dao + all the architecture of ve-governance.
        VeGovernanceFactory factory = new VeGovernanceFactory(params);
        factory.deployOnce();

        printDeploymentSummary(factory);

        vm.stopBroadcast();
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

    function printDeploymentSummary(VeGovernanceFactory factory) internal view {
        DeploymentParameters memory deploymentParameters = factory.getDeploymentParameters();
        Deployment memory deployment = factory.getDeployment();

        console.log("");
        console.log("Deployed from: ", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Factory:", address(factory));
        console.log("");
        console.log("DAO:", address(deployment.dao));
        console.log("");

        console.log("Plugins");
        console.log("- Multisig plugin:", address(deployment.multisigPlugin));
        console.log("");

        for (uint256 i = 0; i < deployment.gaugeVoterPluginSets.length;) {
            console.log("- Using token:", address(deploymentParameters.tokenParameters[i].token));
            console.log("  Gauge voter plugin:", address(deployment.gaugeVoterPluginSets[i].plugin));
            console.log("  Curve:", address(deployment.gaugeVoterPluginSets[i].curve));
            console.log("  Exit Queue:", address(deployment.gaugeVoterPluginSets[i].exitQueue));
            console.log("  Voting Escrow:", address(deployment.gaugeVoterPluginSets[i].votingEscrow));
            console.log("  Clock:", address(deployment.gaugeVoterPluginSets[i].clock));
            console.log("  NFT Lock:", address(deployment.gaugeVoterPluginSets[i].nftLock));
            console.log("  Escrow IVotes Adapter:", address(deployment.gaugeVoterPluginSets[i].delegationAdapter));
            console.log("");

            unchecked {
                i++;
            }
        }

        console.log("Plugin repositories");
        console.log("- Multisig plugin repository (existing):", address(deploymentParameters.multisigPluginRepo));
        console.log("- Gauge voter plugin repository:", address(deployment.gaugeVoterPluginRepo));
    }
}
