// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { console2 as console } from "forge-std/Script.sol";
import { StdStorage, stdStorage } from "forge-std/StdStorage.sol";
import { Vm } from "forge-std/Vm.sol";
import { AddressGaugeVoter } from "@voting/AddressGaugeVoter.sol";
import { LinearIncreasingCurve as Curve } from "@curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@delegation/EscrowIVotesAdapter.sol";
import { AvKATVault } from "src/AvKATVault.sol";
import { VKatMetadata } from "src/VKatMetadata.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IEscrowCurveMath } from "@curve/IEscrowCurveIncreasing.sol";
import { ILock } from "@lock/ILock.sol";
import { Batch1Actions } from "./Batch1Actions.s.sol";
import { Batch2Actions } from "./Batch2Actions.s.sol";
import { BaseScript, IMultisig, IKatToken } from "./BaseScript.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/**
 * @title VerifyDeployment
 * @notice Script to verify and describe all deployed contracts in the Katana Governance ecosystem
 * @dev Run with: forge script script/Verify.s.sol --rpc-url $RPC_URL
 */
contract VerifyDeployment is BaseScript {
    using stdStorage for StdStorage;

    function run() public {
        verifyPausedStates();
        verifyMultisigMembership();
        verifyCurveIsFlat();
        verifyNftLockWhitelist();
        verifyEscrowSplitEnabled();
        verifyExitQueueSettings();
        verifyEscrowMinDeposit();
        assert(AvKATVault(VAULT).masterTokenId() == 0);
        
        // 1. creates batch1 actions proposal on aragon multisig 
        // which creates proposal on katana multisig.
        // 2. execute proposal on katana multisig
        {
            Action[] memory actions = (new Batch1Actions()).generateActions();
            uint256 proposalId = createProposalOnKatanaMultisig("Batch 1", actions);

            vm.startPrank(ARAGON_DAO);
            IMultisig(MULTISIG_PLUGIN).approve(proposalId, false);
            IMultisig(MULTISIG_PLUGIN).execute(proposalId);
            vm.stopPrank();
            verifyMultisigMinApprovalIncrease();
            verifyDynamicExitFeeSettings();
        }

        vm.roll(block.number + 10);

        // Make KAT transferable and transfer it to the DAO.
        unlockAndMintTokensAndTransferToDAO();

        // 1. creates batch2 actions proposal on aragon multisig 
        // which creates proposal on katana multisig.
        // 2. execute proposal on katana multisig
        {
            Action[] memory actions = (new Batch2Actions()).generateActions();
            uint256 proposalId = createProposalOnKatanaMultisig("Bootstrap", actions);

            vm.prank(ARAGON_DAO);
            IMultisig(MULTISIG_PLUGIN).approve(proposalId, false);

            vm.prank(KAT_MEMBER_1);
            IMultisig(MULTISIG_PLUGIN).approve(proposalId, false);

            vm.prank(KAT_MEMBER_2);
            IMultisig(MULTISIG_PLUGIN).approve(proposalId, false);

            IMultisig(MULTISIG_PLUGIN).execute(proposalId);

            verifyPausedStates();
            assert(AvKATVault(VAULT).masterTokenId() == 1);
        }
    }

    // This creates multisig proposal on the katana multisig
    function createProposalOnKatanaMultisig(
        string memory metadata,
        Action[] memory actions
    ) internal returns (uint256 proposalId) {
        IMultisig multisig = IMultisig(ARAGON_MULTISIG_PLUGIN);

        vm.startPrank(ARAGON_MEMBER_1);
        uint256 aragonProposalId = multisig.createProposal(
            bytes(metadata),
            actions,
            0, // allowFailureMap - all actions must succeed
            false, // approveProposal - approve with Aragon DAO's signature
            false, // tryExecution - don't try to execute immediately
            uint64(0), // startDate - 0 means now
            uint64(block.timestamp + 5 days) // endDate - 5 days from now
        );

        multisig.approve(aragonProposalId, false);

        vm.recordLogs();
        multisig.execute(aragonProposalId);
        proposalId = getLatestProposalId();
        vm.stopPrank();
    }

    function getLatestProposalId() internal returns (uint256 proposalId) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // ProposalCreated event signature - tuple should be encoded as (address,uint256,bytes)
        bytes32 proposalCreatedSig = keccak256("ProposalCreated(uint256,address,uint64,uint64,bytes,(address,uint256,bytes)[],uint256)");

        // Search for the ProposalCreated event from the main multisig
        for (uint i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == proposalCreatedSig && logs[i - 1].emitter == MULTISIG_PLUGIN) {
                // First topic is the event signature, second is the indexed proposalId
                proposalId = uint256(logs[i - 1].topics[1]);
                return proposalId;
            }
        }

        revert("ProposalCreated event not found");
    }

    function unlockAndMintTokensAndTransferToDAO() internal {
        IKatToken katToken = IKatToken(TOKEN);
        uint256 amount = 10e18; // 10 tokens

        // Unlock the token
        if (!katToken.isUnlocked()) {
            address unlocker = katToken.roleHolder(katToken.UNLOCKER());
            vm.prank(unlocker);
            katToken.unlockAndRenounceUnlocker();
        }

        katToken.distributeInflation();

        address beneficiary = katToken.roleHolder(katToken.INFLATION_BENEFICIARY());
        vm.prank(beneficiary);
        IERC20Metadata(TOKEN).transfer(DAO, amount);
    }

    function verifyMultisigMinApprovalIncrease() internal view {
        IMultisig multisig = IMultisig(MULTISIG_PLUGIN);
        IMultisig.MultisigSettings memory settings = multisig.multisigSettings();

        assert(settings.minApprovals == 3);
        assert(settings.onlyListed == true);
    }

    function verifyPausedStates() internal view {
        assert(AvKATVault(VAULT).paused() == true);
        assert(VotingEscrow(VOTING_ESCROW).paused() == true);
        assert(VotingEscrow(ESCROW_IVOTES_ADAPTER).paused() == true);
        assert(AddressGaugeVoter(GAUGE_VOTER_PLUGIN).paused() == true);
    }

    function verifyMultisigMembership() internal view {
        IMultisig multisig = IMultisig(MULTISIG_PLUGIN);
        bool isMember = multisig.isMember(ARAGON_DAO);
        IMultisig.MultisigSettings memory settings = multisig.multisigSettings();

        assert(isMember == true);
        assert(settings.onlyListed == true);
        assert(settings.minApprovals == 1);
    }

    function verifyCurveIsFlat() internal view {
        IEscrowCurveMath curve = IEscrowCurveMath(CURVE);
        int256[3] memory coefficients = curve.getCoefficients(1 ether);
        assert(coefficients[0] == 1 ether); // constant
        assert(coefficients[1] == 0); // slope
        assert(coefficients[2] == 0); // quadratic
    }

    function verifyNftLockWhitelist() internal view {
        Lock lock = Lock(NFT_LOCK);
        address whitelistAnyAddress = lock.WHITELIST_ANY_ADDRESS();
        bool isWhitelistedForAll = lock.whitelisted(whitelistAnyAddress);
        bool isVaultWhitelisted = lock.whitelisted(VAULT);
        bool isStrategyWhitelisted = lock.whitelisted(COMPOUND_STRATEGY);

        assert(isWhitelistedForAll == false);
        assert(isVaultWhitelisted == true);
        assert(isStrategyWhitelisted == true);
    }

    function verifyEscrowSplitEnabled() internal view {
        VotingEscrow escrow = VotingEscrow(VOTING_ESCROW);
        address splitWhitelistAnyAddress = escrow.SPLIT_WHITELIST_ANY_ADDRESS();
        bool isSplitEnabledForAll = escrow.splitWhitelisted(splitWhitelistAnyAddress);
        bool isSplitEnabledForStrategy = escrow.splitWhitelisted(COMPOUND_STRATEGY);

        assert(isSplitEnabledForAll == false);
        assert(isSplitEnabledForStrategy == true);
    }

    function verifyExitQueueSettings() internal view {
        ExitQueue queue = ExitQueue(EXIT_QUEUE);
        uint256 feePercent = queue.feePercent();
        uint48 cooldown = queue.cooldown();
        uint48 minLock = queue.minLock();

        assert(feePercent == 2500); // 25% in basis points
        assert(cooldown == 45 days); // 45 days in seconds
        assert(minLock == 1 days); // 1 day in seconds
    }

    function verifyDynamicExitFeeSettings() internal view {
        ExitQueue queue = ExitQueue(EXIT_QUEUE);
        uint256 minFeePercent = queue.minFeePercent();
        uint256 maxFeePercent = queue.feePercent();
        uint48 cooldown = queue.cooldown();
        uint48 minCooldown = queue.minCooldown();

        // Verify dynamic fee settings from GenerateGovernanceActions
        assert(minFeePercent == 250); // 2.5% in basis points
        assert(maxFeePercent == 2500); // 25% in basis points
        assert(cooldown == 45 days); // 45 days
        assert(minCooldown == 0); // 0 days
    }

    function verifyEscrowMinDeposit() internal view {
        VotingEscrow escrow = VotingEscrow(VOTING_ESCROW);
        uint256 minDeposit = escrow.minDeposit();

        assert(minDeposit == 10e18); // 10 tokens with 18 decimals
    }
}
