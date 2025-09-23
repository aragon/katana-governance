// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20Upgradeable as ERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC4626Upgradeable as ERC4626 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PermissionLib } from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";

import { VotingEscrow, EscrowIVotesAdapter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Multisig } from "@aragon/multisig-plugin/Multisig.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import { Distributor as MerklDistributor } from "@merkl/Distributor.sol";
import { AccessControlManager } from "@merkl/AccessControlManager.sol";

import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";
import { AutoCompoundStrategy } from "src/AutoCompoundStrategy.sol";
import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";
import { AvKATVault } from "src/AvKATVault.sol";
import { VKatMetadata } from "src/VKatMetadata.sol";
import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";

import { AutoCompoundStrategy } from "src/AutoCompoundStrategy.sol";
import { Swapper } from "src/Swapper.sol";

import {
    deployVault,
    deploySwapper,
    deployAutoCompoundStrategy,
    deployVKatMetadata,
    deployMerklDistributor
} from "src/utils/Deployers.sol";

struct BaseContracts {
    address merklDistributor;
    address vault;
    address autoCompoundStrategy;
    address vkatMetadata;
}

struct DeploymentParameters {
    address acm;
    address dao;
    address escrow;
    address executor;
    address multisigPlugin;
}

struct Deployment {
    address merklDistributor;
    address vault;
    address autoCompoundStrategy;
    address swapper;
    address vkatMetadata;
}

contract Factory {
    using ProxyLib for address;

    address private owner;

    BaseContracts internal bases;

    DeploymentParameters parameters;
    Deployment deps;

    constructor(BaseContracts memory _bases) {
        owner = msg.sender;

        bases = _bases;
    }

    function deployOnce(DeploymentParameters memory _params) public returns (Deployment memory) {
        if (owner != msg.sender) {
            revert("NotOwner");
        }

        // ======== Deploys Vkat Related contracts ========

        deps.merklDistributor = bases.merklDistributor.deployUUPSProxy(
            abi.encodeCall(MerklDistributor.initialize, AccessControlManager(_params.acm))
        );

        address tokenA = address(new MockERC20());
        address tokenB = address(new MockERC20());
        address tokenC = address(new MockERC20());
        MockERC20(tokenA).mint(address(deps.merklDistributor), 1000e18);
        MockERC20(tokenB).mint(address(deps.merklDistributor), 1000e18);

        deps.vault = bases.vault.deployUUPSProxy(
            abi.encodeCall(
                AvKATVault.initialize,
                (
                    _params.dao,
                    _params.escrow,
                    address(0),
                    VotingEscrow(_params.escrow).token(),
                    "Autocompounding veKAT",
                    "avKAT"
                )
            )
        );

        // deploy swapper
        deps.swapper = deploySwapper(deps.merklDistributor, _params.escrow, _params.executor);

        deps.vkatMetadata = bases.vkatMetadata.deployUUPSProxy(
            abi.encodeCall(
                VKatMetadata.initialize,
                (
                    _params.dao,
                    VotingEscrow(_params.escrow).lockNFT(),
                    new address[](0),
                    IVKatMetadata.VKatMetaDataV1(new uint16[](0), new address[](0))
                )
            )
        );

        deps.autoCompoundStrategy = bases.autoCompoundStrategy.deployUUPSProxy(
            abi.encodeCall(
                AutoCompoundStrategy.initialize,
                (_params.dao, _params.escrow, deps.swapper, deps.vault, deps.merklDistributor)
            )
        );

        Action[] memory actions = getActions(_params.dao, deps, _params.multisigPlugin);

        Multisig multisig = Multisig(address(_params.multisigPlugin));
        multisig.createProposal(
            bytes("initial proposal"), actions, 0, true, true, uint64(block.timestamp), uint64(block.timestamp + 7 days)
        );

        return deps;
    }

    function getActions(
        address _dao,
        Deployment memory _deps,
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
            where: _deps.vkatMetadata,
            who: _dao,
            permissionId: VKatMetadata(_deps.vkatMetadata).ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // compound strategy permissions
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.autoCompoundStrategy,
            who: _dao,
            permissionId: AutoCompoundStrategy(_deps.autoCompoundStrategy).AUTOCOMPOUND_STRATEGY_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // vault permissions
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.vault,
            who: _dao,
            permissionId: AvKATVault(_deps.vault).VAULT_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.vault,
            who: _dao,
            permissionId: AvKATVault(_deps.vault).SWEEPER_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        actions[0].to = _dao;
        actions[0].data = abi.encodeCall(PermissionManager.applyMultiTargetPermissions, permissions);

        actions[1].to = _deps.vault;
        actions[1].data = abi.encodeCall(AvKATVault.setStrategy, _deps.autoCompoundStrategy);

        address[] memory addrs = new address[](1);
        addrs[0] = address(this);
        actions[2].to = _multisig;
        actions[2].data = abi.encodeCall(Multisig.removeAddresses, (addrs));

        return actions;
    }
}
