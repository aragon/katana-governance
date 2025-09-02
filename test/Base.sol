// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/VKatMetadata.sol";
import "../src/interfaces/IVKatMetadata.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { MockDAO } from "./mocks/MockDAO.sol";
import { MockVKatERC721 } from "./mocks/MockVKatERC721.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import {
    GaugesDaoFactoryV1_4_0 as VeGovernanceFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "@factory/GaugesDaoFactory_v1_4_0.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { Multisig } from "@aragon/multisig-plugin/Multisig.sol";

import { GaugeVoterSetupV1_4_0 as GaugeVoterSetup } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";

import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";

contract Base is Test {
    ProtocolFactoryBuilder builder;
    ProtocolFactory.Deployment internal osxDeployment;
    Deployment internal veDeployment;

    DAO internal dao;
    address internal escrowIVotesAdapter;
    Multisig internal multisig;

    function setUp() public virtual {
        _deployOsx();
        _deployVe();

        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 20);
    }

    function _deployOsx() internal {
        builder = new ProtocolFactoryBuilder();
        builder.withMultisigPlugin(1, 1, "ipfs://", "ipfs://", "multisig-subdomain");
        ProtocolFactory protocolFactory = builder.build();
        protocolFactory.deployOnce();
        osxDeployment = protocolFactory.getDeployment();
    }

    function _deployVe() internal {
        address[] memory multisigMembers = new address[](1);
        multisigMembers[0] = address(this);

        TokenParameters[] memory tokenParameters = new TokenParameters[](1);
        tokenParameters[0] = TokenParameters({
            token: createTestToken(multisigMembers),
            veTokenName: "VE Token 1",
            veTokenSymbol: "veTK1"
        });

        int256[3] memory coefficients;
        coefficients[0] = 1000000000000000000;
        coefficients[1] = 0;
        coefficients[2] = 0;

        address gaugeVoterPluginSetup = address(
            new GaugeVoterSetup(
                address(new GaugeVoter()),
                address(new Curve(coefficients, 0)),
                address(new ExitQueue()),
                address(new VotingEscrow()),
                address(new Clock()),
                address(new Lock()),
                address(new EscrowIVotesAdapter())
            )
        );

        DeploymentParameters memory parameters = DeploymentParameters({
            minApprovals: 1,
            multisigMembers: multisigMembers,
            multisigMetadata: "ipfs://io",
            tokenParameters: tokenParameters,
            feePercent: 1,
            cooldownPeriod: 1,
            minLockDuration: 1,
            votingPaused: false,
            minDeposit: 1,
            multisigPluginRepo: PluginRepo(osxDeployment.multisigPluginRepo),
            multisigPluginRelease: 1,
            multisigPluginBuild: 1,
            voterPluginSetup: GaugeVoterSetup(gaugeVoterPluginSetup),
            voterEnsSubdomain: "voter-sub-domain",
            osxDaoFactory: osxDeployment.daoFactory,
            pluginSetupProcessor: PluginSetupProcessor(osxDeployment.pluginSetupProcessor),
            pluginRepoFactory: PluginRepoFactory(osxDeployment.pluginRepoFactory)
        });

        VeGovernanceFactory veGovFactory = new VeGovernanceFactory(parameters);
        veGovFactory.deployOnce();

        Deployment memory deps = veGovFactory.getDeployment();
        dao = deps.dao;
        escrowIVotesAdapter = address(deps.gaugeVoterPluginSets[0].delegationAdapter);
        multisig = Multisig(address(deps.multisigPlugin));
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint256 i = 0; i < holders.length; i++) {
            newToken.mint(holders[i], 5000 ether);
        }

        return address(newToken);
    }

    function _createProposal(address _to, bytes memory _data) internal {
        Action[] memory actions = new Action[](1);
        actions[0].to = _to;
        actions[0].data = _data;
        multisig.createProposal("", actions, 0, true, true, 0, uint64(block.timestamp + 1 days));
    }
}
