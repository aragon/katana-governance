// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../src/VKatMetadata.sol";
import "../../src/interfaces/IVKatMetadata.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { MockDAO } from "../mocks/MockDAO.sol";
import { MockVKatERC721 } from "../mocks/MockVKatERC721.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import { AvKATVault } from "../../src/AvKATVault.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";

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
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import { Executor } from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import { GaugeVoterSetupV1_4_0 as GaugeVoterSetup } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { AddressGaugeVoter as GaugeVoter } from "@voting/AddressGaugeVoter.sol";

import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";

import { Distributor as MerklDistributor } from "@merkl/Distributor.sol";
import { AccessControlManager } from "@merkl/AccessControlManager.sol";
import { MerkleTree } from "../utils/merkle/MerkleTree.sol";
import { Swapper } from "../../src/Swapper.sol";
import { MockSwap } from "../mocks/MockSwap.sol";

contract Base is ERC721Holder, Test {
    using ProxyLib for address;

    // Deployment Objects
    ProtocolFactoryBuilder builder;
    ProtocolFactory.Deployment internal osxDeployment;
    Deployment internal veDeployment;

    // ve contracts
    DAO internal dao;
    address internal ivotesAdapter;
    VotingEscrow internal escrow;
    Multisig internal multisig;
    Lock internal lockNft;

    // kat contracts
    MockERC20 internal token;
    uint256 internal masterTokenId;
    AvKATVault public vault;
    Swapper internal swapper;
    uint8 internal decimals;

    // merkl contracts
    AccessControlManager internal acm;
    MerklDistributor internal merklDistributor;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MerkleTree internal merkleTree;

    // other
    MockSwap internal mockSwap;
    Executor internal executor;

    // some user addresses
    address internal alice = address(3);
    address internal bob = address(4);
    address internal charlie = address(5);
    address internal john = address(6);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    event TokenIdWithdrawn(uint256 tokenId, address receiver);

    function setUp() public virtual {
        _deployOsx();
        _deployVe();
        _deployMerklDistributor();

        vm.warp(block.timestamp + 20);
        vm.roll(block.number + 20);

        executor = new Executor();

        _deployVault();
        _deploySwapper();
        mockSwap = new MockSwap();

        token = MockERC20(vault.asset());

        vault.initialize(masterTokenId);
    }

    function _deployMerklDistributor() internal {
        acm = AccessControlManager(
            address(new AccessControlManager()).deployUUPSProxy(
                abi.encodeCall(AccessControlManager.initialize, (address(this), alice))
            )
        );
        merklDistributor = MerklDistributor(
            address(new MerklDistributor()).deployUUPSProxy(abi.encodeCall(MerklDistributor.initialize, acm))
        );

        merkleTree = new MerkleTree();

        tokenA = new MockERC20();
        tokenB = new MockERC20();

        tokenA.mint(address(merklDistributor), 1000e18);
        tokenB.mint(address(merklDistributor), 1000e18);
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
        ivotesAdapter = address(deps.gaugeVoterPluginSets[0].delegationAdapter);
        escrow = deps.gaugeVoterPluginSets[0].votingEscrow;
        lockNft = deps.gaugeVoterPluginSets[0].nftLock;
        multisig = Multisig(address(deps.multisigPlugin));
        token = MockERC20(tokenParameters[0].token);
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint256 i = 0; i < holders.length; i++) {
            newToken.mint(holders[i], 5000 ether);
        }

        decimals = newToken.decimals();

        return address(newToken);
    }

    function _createProposal(Action[] memory _actions) internal {
        multisig.createProposal("", _actions, 0, true, true, 0, uint64(block.timestamp + 1 days));
    }

    function _deployVault() internal {
        vault = new AvKATVault(
            address(dao), address(ivotesAdapter), address(0), address(escrow.token()), "Autocompounding veKAT", "avKAT"
        );

        Action[] memory actions = new Action[](4);
        actions[0].to = address(dao);
        actions[0].data =
            abi.encodeCall(PermissionManager.grant, (address(vault), address(this), vault.VAULT_ADMIN_ROLE()));

        actions[1].to = address(dao);
        actions[1].data = abi.encodeCall(PermissionManager.grant, (address(vault), address(this), vault.SWEEPER_ROLE()));

        actions[2].to = address(dao);
        actions[2].data =
            abi.encodeCall(PermissionManager.grant, (address(lockNft), address(this), lockNft.LOCK_ADMIN_ROLE()));

        actions[3].to = address(dao);
        actions[3].data =
            abi.encodeCall(PermissionManager.grant, (address(escrow), address(this), escrow.ESCROW_ADMIN_ROLE()));

        _createProposal(actions);

        lockNft.setWhitelisted(address(vault), true);
        escrow.enableSplit();

        token.approve(address(escrow), 100 * 10 ** 18);
        masterTokenId = escrow.createLock(100 * 10 ** 18);
        lockNft.transferFrom(address(this), address(vault), masterTokenId);
    }

    function _deploySwapper() internal {
        swapper = new Swapper(address(merklDistributor), address(escrow), address(executor));
    }

    function _mintAndApprove(address _account, address _who, uint256 _amount) internal {
        token.mint(_account, _amount);
        vm.prank(_account);
        token.approve(_who, _amount);
    }

    function _parseToken(uint256 _amount) internal view returns (uint256) {
        return _amount * 10 ** decimals;
    }

    function _increaseTotalAsset(uint256 _amount) internal {
        _mintAndApprove(address(this), address(escrow), _amount);
        uint256 tokenId = escrow.createLockFor(_amount, address(vault));
        vm.startPrank(address(vault));
        escrow.merge(tokenId, vault.masterTokenId());
        vm.stopPrank();
    }
}
