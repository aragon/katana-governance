// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Mock contract that accepts ETH for testing payable functions
contract PayableReceiver {
    event EthReceived(address sender, uint256 amount);

    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    function receiveEth() external payable {
        emit EthReceived(msg.sender, msg.value);
    }
}
