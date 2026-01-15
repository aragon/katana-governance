// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Script, console2 as console } from "forge-std/Script.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PluginSetupProcessor } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

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
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { AvKATVault } from "src/AvKATVault.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

import {
    Factory as KatFactory,
    DeploymentParameters as KatDeploymentParams,
    Deployment as KatDeployment,
    BaseContracts
} from "src/Factory.sol";

import { DefaultStrategy } from "src/strategies/DefaultStrategy.sol";

import { IExecutor, Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

interface IMultisig {
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        bool _approveProposal,
        bool _tryExecution,
        uint64 _startDate,
        uint64 _endDate
    )
        external
        returns (uint256 proposalId);
}

contract VoteTest is Script {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    // Hardcoded addresses - replace these with actual values
    address constant MULTISIG_ADDRESS = address(0x8ADBEd9880b9BfE6960fD2594148373816b0193E);
    address constant STRATEGY = address(0xf8Ff17c358f27c10Bb52689941C75E47E35CED05);
    address constant DELEGATEE = address(0xA15b85b8bA4b756fC8C1FD9c774A14008E0547CA);
    address constant DAO = address(0x8147C72d9E827f01C8b62cf55b9A6e637C2bf11B);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Create actions array
        Action[] memory actions = new Action[](2);

        actions[0] = Action({ to: STRATEGY, value: 0, data: abi.encodeWithSignature("delegate(address)", DELEGATEE) });

        actions[1] = Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "grant(address,address,bytes32)", STRATEGY, DELEGATEE, keccak256("AUTOCOMPOUND_STRATEGY_VOTE_ROLE")
            )
        });

        // Create proposal on multisig
        IMultisig multisig = IMultisig(MULTISIG_ADDRESS);
        uint256 proposalId = multisig.createProposal(
            bytes("Unpause vault and initialize master token"), // metadata
            actions,
            0, // allowFailureMap - 0 means all actions must succeed
            true, // approveProposal - automatically approve with your address
            true, // tryExecution - don't try to execute immediately
            0, // startDate - 0 means now
            uint64(block.timestamp + 7 days) // endDate - 0 means use default from settings
        );

        console.log("Proposal created with ID:", proposalId);

        vm.stopBroadcast();
    }
}
