// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { BaseScript } from "./BaseScript.sol";

contract Batch2Actions is BaseScript {
    // Constants specific to this batch
    uint256 constant TOKEN_ID = 1;
    uint256 constant INITIAL_DEPOSIT = 10e18; // 10 tokens

    function run() public returns (Action[] memory) {
        return generateActions();
    }

    function generateActions() public returns (Action[] memory) {
        // Create actions array - 7 actions total
        Action[] memory actions = new Action[](9);

        // Action 0: Transfer 10 KAT to DAO
        // The DAO must have 10 KAT to create a vKAT position
        actions[0] = Action({
            to: TOKEN,
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", DAO, INITIAL_DEPOSIT)
        });

        // Action 1: Unpause VotingEscrow
        // Must be done before initializing the vault
        actions[1] = Action({
            to: VOTING_ESCROW,
            value: 0,
            data: abi.encodeWithSignature("unpause()")
        });

        // Action 2: DAO approves Escrow to spend its tokens.
        actions[2] = Action({
            to: TOKEN,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", VOTING_ESCROW, INITIAL_DEPOSIT)
        });

        // Action 3: unpause ivotes adapter. needed for createLockFor.
        actions[3] = Action({
            to: ESCROW_IVOTES_ADAPTER,
            value: 0,
            data: abi.encodeWithSignature("unpause()")
        });

        // Action 4: Create vKAT position for DAO
        // Creates the vKAT position which will be sent to the strategy as a masterTokenId
        actions[4] = Action({
            to: VOTING_ESCROW,
            value: 0,
            data: abi.encodeWithSignature("createLockFor(uint256,address)", INITIAL_DEPOSIT, DAO)
        });

        // Action 5: DAO approves avKATVault to use tokenId
        // Needed for the next action (initializeMasterTokenAndStrategy)
        actions[5] = Action({
            to: NFT_LOCK,
            value: 0,
            data: abi.encodeWithSignature("approve(address,uint256)", VAULT, TOKEN_ID)
        });

        // Action 6: Initialize vault with master token and strategy
        // Initializes the vault, moves the tokenId from DAO to its own address,
        // and mints shares to the sender (DAO). This prevents inflation attacks.
        actions[6] = Action({
            to: VAULT,
            value: 0,
            data: abi.encodeWithSignature("initializeMasterTokenAndStrategy(uint256,address)", TOKEN_ID, COMPOUND_STRATEGY)
        });

        // Action 7: Pause VotingEscrow
        // Optional but recommended - prevents other deposits until rest of system is live
        actions[7] = Action({
            to: VOTING_ESCROW,
            value: 0,
            data: abi.encodeWithSignature("pause()")
        });

        // Action 8: pause the ivotes adapter
        actions[8] = Action({
            to: ESCROW_IVOTES_ADAPTER,
            value: 0,
            data: abi.encodeWithSignature("pause()")
        });

        bytes memory proposalData = createProposalData(
            "Bootstrap Katana Vault",
            actions
        );

        Action[] memory wrapperAction = new Action[](1);
        wrapperAction[0] = Action({
            to: MULTISIG_PLUGIN,
            value: 0,
            data: proposalData
        });

        // Serialize and write to JSON file
        string memory actionsJson = _serializeActions(wrapperAction);
        vm.writeJson(actionsJson, "./deployments/batch-2.json");

        return wrapperAction;
    }
}
