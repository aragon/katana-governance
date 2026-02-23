// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { BaseScript } from "./BaseScript.sol";

contract Batch1Actions is BaseScript {
    function run() public returns (Action[] memory) {
        return generateActions();
    }

    function generateActions() public returns (Action[] memory) {
        // Create actions array - 7 actions total
        Action[] memory actions = new Action[](6);

        // Action 0: Unpause IVotesAdapter
        actions[0] = Action({
            to: ESCROW_IVOTES_ADAPTER,
            value: 0,
            data: abi.encodeWithSignature("unpause()")
        });

        // Action 1: Delegate to strategy
        actions[1] = Action({
            to: COMPOUND_STRATEGY,
            value: 0,
            data: abi.encodeWithSignature("delegate(address)", COMPOUND_STRATEGY)
        });

        // Action 2: Set dynamic exit fee percent
        // Parameters: minFeePercent=250 (2.5%), maxFeePercent=2500 (25%), cooldown=45 days, minCooldown=0
        actions[2] = Action({
            to: EXIT_QUEUE,
            value: 0,
            data: abi.encodeWithSignature(
                "setDynamicExitFeePercent(uint256,uint256,uint48,uint48)", 250, 2500, 45 days, 1
            )
        });

        // Action 3: Grant AUTOCOMPOUND_STRATEGY_VOTE_ROLE to VOTER
        actions[3] = Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "grant(address,address,bytes32)", COMPOUND_STRATEGY, VOTER, AUTOCOMPOUND_STRATEGY_VOTE_ROLE
            )
        });

        // Action 4: Grant AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE to CLAIMER
        actions[4] = Action({
            to: DAO,
            value: 0,
            data: abi.encodeWithSignature(
                "grant(address,address,bytes32)",
                COMPOUND_STRATEGY,
                CLAIMER,
                AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE
            )
        });

        // Action 5: Pause IVotesAdapter back
        actions[5] = Action({
            to: ESCROW_IVOTES_ADAPTER,
            value: 0,
            data: abi.encodeWithSignature("pause()")
        });

        bytes memory proposalData = createProposalData(
            hex"697066733a2f2f6261666b7265696466746f71776c356f6a6c37747869676c7136326d3272697064686572706b74327036746e6a6e65616b693768797a6f37677979",
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
        vm.writeJson(actionsJson, "./deployments/batch-1.json");

        return wrapperAction;
    }
}
