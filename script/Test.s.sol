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

contract ProposalDeploy is Script {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    // Hardcoded addresses - replace these with actual values
    address constant MULTISIG_ADDRESS = address(0xe4f642224FAf2E87F02EB40cfE7Ab91f770A2FD3);
    address constant AVKAT_VAULT_ADDRESS = address(0xBB5874022AE19E2060b4bED1f310cB8e4a677fD9);
    address constant NFT_LOCK_ADDRESS = address(0xaA8D197A85E5959DBff5fC46aCd48B688b017fdf);
    address constant STRATEGY = address(0xC0335ca3E780E7C13d58277122172cfBD16ED853);
    address constant GAUGE_VOTER = address(0xaE81b374571B4Fe3a158b43317dF416f58875935);
    address constant ESCROW = address(0x879aE78AB877e5CB0613410654e8ce17B6d91489);
    address constant DELEGATEE = address(0xb275d7CD2511628661e540288718e86bF0cE2270);
    address constant DAO = address(0xD571Ff4e20a52366176666DbEd34011ba3edba43);
    address constant TOKEN = address(0x1B6e79f9DA388387eD67A89Cba06948E78d16796);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        MockERC20(TOKEN).approve(ESCROW, 5e18);
        uint256 tokenId = VotingEscrow(ESCROW).createLockFor(5e18, DAO);

        // Create actions array
        Action[] memory actions = new Action[](9);

        /// AvKatVault Initialization
        actions[0] = Action({ to: AVKAT_VAULT_ADDRESS, value: 0, data: abi.encodeWithSignature("unpause()") });
        actions[1] = Action({
            to: NFT_LOCK_ADDRESS,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", AVKAT_VAULT_ADDRESS, tokenId)
        });
        actions[2] = Action({
            to: AVKAT_VAULT_ADDRESS,
            value: 0,
            data: abi.encodeWithSignature("initializeMasterTokenAndStrategy(uint256,address)", tokenId, STRATEGY)
        });

        // CompoundStrategy
        actions[3] = Action({ to: STRATEGY, value: 0, data: abi.encodeWithSignature("delegate(address)", DELEGATEE) });

        actions[4] = Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "grant(address,address,bytes32)", STRATEGY, DELEGATEE, keccak256("AUTOCOMPOUND_STRATEGY_VOTE_ROLE")
            )
        });

        actions[5] = Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "grant(address,address,bytes32)",
                STRATEGY,
                DELEGATEE,
                keccak256("AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE")
            )
        });

        // Escrow enable split.
        actions[6] = Action({ to: ESCROW, value: 0, data: abi.encodeWithSignature("enableSplit()") });

        // GaugeVoter
        actions[7] = Action({
            to: GAUGE_VOTER,
            value: 0,
            data: abi.encodeWithSignature("createGauge(address,string)", address(12), "gauge1")
        });
        actions[8] = Action({
            to: GAUGE_VOTER,
            value: 0,
            data: abi.encodeWithSignature("createGauge(address,string)", address(13), "gauge2")
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
