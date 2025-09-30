pragma solidity ^0.8.17;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { Base } from "../Base.sol";
import { SwapperHandler as Handler } from "./SwapperHandler.sol";

import { StdInvariant } from "forge-std/StdInvariant.sol";

contract SwapperInvariant is StdInvariant, Base {
    Handler internal h;

    function setUp() public override {
        super.setUp();

        h = new Handler(swapper, merkleTreeHelper);

        targetContract(address(h));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.claimAndSwap.selector;
        FuzzSelector memory a = FuzzSelector(address(h), selectors);
        targetSelector(a);
    }

    function invariant_TotalLockedCorrect() public view { }
}
