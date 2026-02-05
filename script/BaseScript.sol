// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { IExecutor, Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

 interface IMultisig {
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
    }

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );

    function isMember(address account) external view returns (bool);
    function multisigSettings() external view returns (MultisigSettings memory);
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        bool _approveProposal,
        bool _tryExecution,
        uint64 _startDate,
        uint64 _endDate
    ) external returns (uint256 proposalId);
    function execute(uint256 _proposalId) external;
    function approve(uint256 _proposalId, bool _tryExecution) external;
    function proposalCount() external view returns (uint256);
}


interface IKatToken {
    function INFLATION_BENEFICIARY() external view returns (bytes32);
    function UNLOCKER() external view returns (bytes32);
    function roleHolder(bytes32 role) external view returns (address);
    function unlockAndRenounceUnlocker() external;
    function isUnlocked() external view returns (bool);
    function mintCapacity(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function distributeMintCapacity(address to, uint256 amount) external;
    function distributeInflation() external;
}

/**
 * @title BaseScript
 * @notice Base contract with shared interfaces, constants, and helper functions for all scripts
 */
abstract contract BaseScript is Script {
    // ====================================================================
    // Deployment Addresses
    // ====================================================================

    // DAO Addresses
    address internal constant DAO = 0xb72291652f15cF73651357383c0A86FBba29B675;
    address internal constant ARAGON_DAO = 0x546ef3A10B303843010417f10d0b025e9AAd70Eb;

    // Plugin Addresses
    address internal constant ARAGON_MULTISIG_PLUGIN = 0xf360D6a082267C2457d0e2EB30992f94271764c0;
    address internal constant MULTISIG_PLUGIN = 0x69f9105DCc43bAaa78089Fcf811aaaD2C156D269;
    address internal constant GAUGE_VOTER_PLUGIN = 0x5e755A3C5dc81A79DE7a7cEF192FFA60964c9352;

    // Token & Governance Contracts
    address internal constant TOKEN = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d;
    address internal constant CURVE = 0x38b8B74330b2F918C22F7936aCf773C6D963C73c;
    address internal constant EXIT_QUEUE = 0x6dE9cAAb658C744aD337Ca5d92D084c97ffF578d;
    address internal constant VOTING_ESCROW = 0x4d6fC15Ca6258b168225D283262743C623c13Ead;
    address internal constant CLOCK = 0x17049d374A2bcdA70F8939C21ad92bcF6B2A95ab;
    address internal constant NFT_LOCK = 0x106F7D67Ea25Cb9eFf5064CF604ebf6259Ff296d;
    address internal constant ESCROW_IVOTES_ADAPTER = 0xB67Ac05e2C1d8592692a90BF61712274b988f25A;

    // Katana Contracts
    address internal constant VAULT = 0x7231dbaCdFc968E07656D12389AB20De82FbfCeB;
    address internal constant SWAPPER = 0x92D2e00b6D2BB50B87a9BE971a82B1F00ac44768;
    address internal constant COMPOUND_STRATEGY = 0x60233D1c150F9C08D886906d597aA79a205b0463;
    address internal constant KAT_METADATA = 0xb2143cFC740356E5FeFB4488e01026cfBb0A328F;

    // Katana Team Members Multisig
    address internal constant KAT_MEMBER_1 = 0xb3dA4c1Ba8De9E04f22B1554a070189F518FDCac;
    address internal constant KAT_MEMBER_2 = 0x34d23C4fb6542B467cA8724bAD30AC811399b184;

    // Aragon Team Members Multisig
    address internal constant ARAGON_MEMBER_1 = 0xd953216D672218db55cAb06c2406D5f8af89D720;

    // Role Grantees
    address internal constant VOTER = COMPOUND_STRATEGY;
    address internal constant CLAIMER = COMPOUND_STRATEGY;

    // Role Hashes
    bytes32 internal constant AUTOCOMPOUND_STRATEGY_VOTE_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_VOTE_ROLE");
    bytes32 internal constant AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_CLAIM_COMPOUND_ROLE");


    function createProposalData(
        string memory metadata,
        Action[] memory actions
    ) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            IMultisig.createProposal.selector,
            bytes(metadata),
            actions,
            0, // allowFailureMap - all actions must succeed
            false, // approveProposal - don't auto-approve
            false, // tryExecution - don't try to execute immediately
            uint64(0), // startDate - 0 means now
            uint64(block.timestamp + 5 days) // endDate
        );
    }

    function _serializeActions(
        Action[] memory _actions
    ) internal pure returns (string memory serialized) {
        string memory json = "[";

        for (uint i = 0; i < _actions.length; i++) {
            Action memory a = _actions[i];

            // Build individual action JSON manually
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(a.to),
                '","value":',
                vm.toString(a.value),
                ',"data":"',
                vm.toString(a.data),
                '"}'
            );

            // Add comma if not last element
            if (i < _actions.length - 1) {
                json = string.concat(json, ",");
            }
        }

        json = string.concat(json, "]");
        return json;
    }
}
