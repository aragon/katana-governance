pragma solidity ^0.8.17;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { CommonBase } from "forge-std/Base.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";

import { Base } from "../integration/Base.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";
import { MerkleTreeHelper } from "../utils/merkle/MerkleTreeHelper.sol";

contract SwapperHandler is StdUtils, StdCheats, CommonBase {
    Swapper internal swapper;
    MerkleTreeHelper internal merkleTreeHelper;
    address internal merklDistributor;

    address[] public actors;
    MockERC20[] public rewardTokens;

    constructor(Swapper _swapper, MerkleTreeHelper _merkleTreeHelper) {
        swapper = _swapper;
        merkleTreeHelper = _merkleTreeHelper;

        // merklDistributor = _merklDistributor;

        // Setup initial actors
        for (uint256 i = 0; i < 3; i++) {
            actors.push(address(uint160(0x1000 + i)));
        }

        // // setup reward tokens
        // for (uint256 i = 0; i < 3; i++) {
        //     rewardTokens.push(new MockERC20());
        //     rewardTokens[i].mint(address(merklDistributor), type(uint128).max);
        // }
    }

    function claimAndSwap(uint256 _actorIndex, uint256 _seed, uint128[] memory _claimAmounts) public {
        // uint256 len = _claimAmounts.length;
        // vm.assume(len <= rewardTokens.length);

        // address actor = actors[bound(_actorIndex, 0, actors.length - 1)];

        // address[] memory tokens = rewardTokensClaimable(_seed, len);
        // bytes32[][] memory proofs = super.buildMerkleTree(actor, tokens, _claimAmounts);

        // ISwapper.Claim memory input = ISwapper.Claim({ tokens: tokens, amounts: _claimAmounts, proofs: proofs });
        // swapper.claimAndSwap(input, new Action[](0), 0);
    }

    function rewardTokensClaimable(
        uint256 _seed,
        uint256 _count
    )
        internal
        view
        returns (address[] memory claimTokens)
    {
        _count = bound(_count, 0, rewardTokens.length - 1);
        address[] memory temp = new address[](_count);

        // shuffle
        for (uint256 i = rewardTokens.length - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encode(_seed, i))) % (i + 1);
            (temp[i], temp[j]) = (temp[j], temp[i]);
        }

        claimTokens = new address[](_count);
        for (uint256 i = 0; i < _count; i++) {
            claimTokens[i] = temp[i];
        }
    }
}
