pragma solidity ^0.8.17;

import { StdUtils } from "forge-std/StdUtils.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { CommonBase } from "forge-std/Base.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Distributor as MerklDistributor, MerkleTree as MerkleTreeStruct } from "@merkl/Distributor.sol";

import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";

import { MerkleTreeHelper } from "../../utils/merkle/MerkleTreeHelper.sol";
import { SwapActionsBuilder } from "../../utils/SwapActionsBuilder.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";
import { console2 as console } from "forge-std/console2.sol";
import { AvKATVault } from "src/AvKATVault.sol";

import { BaseHandler } from "./BaseHandler.sol";

contract AvKatVaultHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public token; // token of escrow.

    AvKATVault internal vault;
    MockERC20 internal assetToken;

    EnumerableSet.AddressSet internal actorsWithDepositedAssets;

    mapping(address => uint256) internal actorAssets;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    constructor(AvKATVault _vault) {
        vault = _vault;

        assetToken = MockERC20(address(vault.asset()));

        totalDeposited = vault.totalAssets();
    }

    function deposit(uint256 _seed, uint256 _amount) public {
        address actor = useSender(_seed);
        _amount = bound(_amount, 1, type(uint128).max);

        deal(address(assetToken), actor, _amount);

        vm.startPrank(actor);
        assetToken.approve(address(vault), _amount);
        uint256 shares = vault.deposit(_amount, actor);
        vm.stopPrank();

        actorsWithDepositedAssets.add(actor);
        actorAssets[actor] += _amount;

        totalDeposited += _amount;
    }

    function withdraw(uint256 _seed, uint256 _amount) public {
        uint256 len = actorsWithDepositedAssets.length();
        if (len == 0) {
            return;
        }

        address actor = actorsWithDepositedAssets.at(_bound(_seed, 0, len - 1));

        if (actorAssets[actor] == 0) {
            return;
        }

        _amount = _bound(_amount, 1, actorAssets[actor]);

        vm.prank(actor);
        vault.withdraw(_amount, actor, actor);

        actorAssets[actor] -= _amount;

        totalWithdrawn += _amount;
    }

    function redeem(uint256 _actorIndex, uint256 _seed, uint256 _count, uint256 _pct) public { }

    // Helper Functions
}
