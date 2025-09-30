pragma solidity ^0.8.17;

import { StdUtils } from "forge-std/StdUtils.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { CommonBase } from "forge-std/Base.sol";

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { Distributor as MerklDistributor, MerkleTree as MerkleTreeStruct } from "@merkl/Distributor.sol";

import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";

import { MerkleTreeHelper } from "../utils/merkle/MerkleTreeHelper.sol";
import { SwapActionsBuilder } from "../utils/SwapActionsBuilder.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";
import { console2 as console } from "forge-std/console2.sol";

contract SwapperHandler is StdUtils, StdCheats, CommonBase {
    Swapper internal swapper;

    MerkleTreeHelper internal merkleTreeHelper;
    SwapActionsBuilder internal swapActionsBuilder;
    MerklDistributor internal merklDistributor;

    address[] public actors;
    address[] public rewardTokens;
    address[] public outTokens;
    address public token; // token of escrow.

    constructor(Swapper _swapper, MerkleTreeHelper _merkleTreeHelper, SwapActionsBuilder _swapActionsBuilder) {
        swapper = _swapper;
        token = address(_swapper.token());

        merkleTreeHelper = _merkleTreeHelper;
        swapActionsBuilder = _swapActionsBuilder;
        merklDistributor = _merkleTreeHelper.merklDistributor();

        // Setup initial actors
        for (uint256 i = 0; i < 3; i++) {
            actors.push(address(uint160(0x1000 + i)));
        }

        // setup reward tokens
        for (uint256 i = 0; i < 5; i++) {
            rewardTokens.push(address(new MockERC20()));
            outTokens.push(address(new MockERC20()));
        }

        outTokens.push(address(token));
        rewardTokens.push(address(token));
    }

    function claimAndSwap(uint256 _actorIndex, uint256 _seed, uint256 _count, uint256 _pct) public {
        _count = _bound(_count, 2, rewardTokens.length);
        _pct = _bound(_pct, 0, 100);
        address actor = actors[_bound(_actorIndex, 0, actors.length - 1)];

        uint256[] memory amounts = new uint256[](_count);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = _bound(amounts[i], 100, 500e18);
        }

        // To ensure more randomness, use `_seed` to
        // grab different  tokens to claim each time.
        address[] memory inTokens = selectRandomTokens(rewardTokens, _seed, _count);
        address[] memory outTokens = selectRandomTokens(outTokens, _seed, _count);
        address[] memory recipients = getRecipients(outTokens, actor);

        // MerklDistributor uses the logic that if one receives more reward(i.e 2nd time),
        // the amount in a tree must also include previous amount(prevAmount + newAmount).
        // Otherwise claiming fails.
        uint256[] memory claimAmounts = new uint256[](inTokens.length);
        for (uint256 i = 0; i < inTokens.length; i++) {
            (uint256 alreadyClaimed,,) = merklDistributor.claimed(actor, inTokens[i]);
            claimAmounts[i] = alreadyClaimed + amounts[i];
        }

        (bytes32[][] memory proofs,) = merkleTreeHelper.buildMerkleTree(actor, inTokens, claimAmounts);
        Action[] memory actions = swapActionsBuilder.buildSwapActions(inTokens, amounts, outTokens, recipients);

        ISwapper.Claim memory input = ISwapper.Claim({ tokens: inTokens, amounts: claimAmounts, proofs: proofs });
        vm.prank(actor, actor);
        swapper.claimAndSwap(input, actions, _pct);
    }

    // Helper Functions
    function allRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }

    function allOutTokens() public view returns (address[] memory) {
        return outTokens;
    }

    function getRecipients(address[] memory _outTokens, address _actor) public view returns (address[] memory) {
        address[] memory recipients = new address[](_outTokens.length);
        for (uint256 i = 0; i < _outTokens.length; i++) {
            if (_outTokens[i] == token) {
                recipients[i] = address(swapper);
                continue;
            }

            recipients[i] = _actor;
        }

        return recipients;
    }

    function selectRandomTokens(
        address[] storage tokens,
        uint256 _seed,
        uint256 _count
    )
        internal
        view
        returns (address[] memory result)
    {
        // First, copy tokens to temp
        address[] memory temp = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            temp[i] = tokens[i];
        }

        // shuffle
        for (uint256 i = tokens.length - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encode(_seed, i))) % (i + 1);
            (temp[i], temp[j]) = (temp[j], temp[i]);
        }

        result = new address[](_count);
        for (uint256 i = 0; i < _count; i++) {
            result[i] = temp[i];
        }
    }
}
