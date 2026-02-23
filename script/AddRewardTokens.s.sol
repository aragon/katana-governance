// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { BaseScript, IMultisig} from "./BaseScript.sol";
import { Vm } from "forge-std/Vm.sol";

contract AddRewardTokensActions is BaseScript {
    function run() public returns (Action[] memory) {
        return generateActions();
    }

    function generateActions() public returns (Action[] memory) {
        // Array of all reward tokens to add
        address[] memory rewardTokens = new address[](20);
        rewardTokens[0] = address(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36); // vbUSDC
        rewardTokens[1] = address(0x2DCa96907fde857dd3D816880A0df407eeB2D2F2); // vbUSDT
        rewardTokens[2] = address(0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62); // vbETH
        rewardTokens[3] = address(0x0913DA6Da4b42f538B445599b46Bb4622342Cf52); // vbWBTC
        rewardTokens[4] = address(0xcA52d08737E6Af8763a2bF6034B3B03868f24DDA); // dUSD
        rewardTokens[5] = address(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUSD
        rewardTokens[6] = address(0xFCeF626dE4A0175ac962DD43EB0A002819FaAEFe); // sYUSD
        rewardTokens[7] = address(0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a); // AUSD
        rewardTokens[8] = address(0xb24e3035d1FCBC0E43CF3143C3Fd92E53df2009b); // POL
        rewardTokens[9] = address(0x0F26bBb8962d73bC891327F14dB5162D5279899F); // KAI
        rewardTokens[10] = address(0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072); // BTC.b
        rewardTokens[11] = address(0x64445f0aecC51E94aD52d8AC56b7190e764E561a); // wFRAX
        rewardTokens[12] = address(0x17BFF452dae47e07CeA877Ff0E1aba17eB62b0aB); // SUSHI
        rewardTokens[13] = address(0x876aac7648D79f87245E73316eB2D100e75F3Df1); // bvUSD
        rewardTokens[14] = address(0x1e5eFCA3D0dB2c6d5C67a4491845c43253eB9e4e); // MORPHO
        rewardTokens[15] = address(0x476eaCd417cD65421bD34fca054377658BB5E02b); // YFI
        rewardTokens[16] = address(0x9B8Df6E244526ab5F6e6400d331DB28C8fdDdb55); // uSOL
        rewardTokens[17] = address(0x2A66d51407b84b82b5AFF3DeC4D49f72CBCD322a); // UTY
        rewardTokens[18] = address(0xFBa805659E5050544e185cccdf592FD77f8c7210); // KITSU
        rewardTokens[19] = address(0xA600A613C967b9EDF2b6019ea300Abc738F88637); // BUSHIDO

        // Create actions array
        Action[] memory actions = new Action[](rewardTokens.length);

        // Loop through tokens and create addRewardToken action for each
        for (uint i = 0; i < rewardTokens.length; i++) {
            actions[i] = Action({
                to: KAT_METADATA,
                value: 0,
                data: abi.encodeWithSignature("addRewardToken(address)", rewardTokens[i])
            });
        }

        bytes memory proposalData = createProposalData(
            hex"697066733a2f2f6261666b726569657162636d6a74746e716c68657a623567687468723432716d757a77616f72637066616773363571646c3575656779776e6a7834",
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
        vm.writeJson(actionsJson, "./deployments/add-reward-tokens.json");
        
        uint256 proposalId = createProposalOnKatanaMultisig("blaxblux", wrapperAction);
        return wrapperAction;
    }
}
