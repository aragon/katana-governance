// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "@mocks/MockERC20.sol";

contract MockSwap {
    event Swapped(address from, address to, uint256 amount);

    function swap(address tokenA, address tokenB, uint256 amount) external {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount);

        // fake 2x swap for testing
        MockERC20(tokenB).mint(address(this), amount * 2);
        IERC20(tokenB).transfer(msg.sender, amount * 2);
    }
}
