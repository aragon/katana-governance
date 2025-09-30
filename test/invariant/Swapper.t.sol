pragma solidity ^0.8.17;

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { Base } from "../Base.sol";
import { SwapperHandler as Handler } from "./SwapperHandler.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract SwapperInvariant is StdInvariant, Base {
    Handler internal h;

    function setUp() public override {
        super.setUp();

        h = new Handler(swapper, merkleTreeHelper, swapActionsBuilder);

        targetContract(address(h));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.claimAndSwap.selector;
        FuzzSelector memory a = FuzzSelector(address(h), selectors);
        targetSelector(a);
    }

    function invariant_SwapperShouldNotHoldAnyTokens() public view {
        assertEq(token.balanceOf(address(swapper)), 0);

        address[] memory rewardTokens = h.allRewardTokens();
        address[] memory outTokens = h.allOutTokens();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            assertEq(MockERC20(rewardTokens[i]).balanceOf(address(swapper)), 0);
        }

        for (uint256 i = 0; i < outTokens.length; i++) {
            assertEq(MockERC20(outTokens[i]).balanceOf(address(swapper)), 0);
        }
    }
}
