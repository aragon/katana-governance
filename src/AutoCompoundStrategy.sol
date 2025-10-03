// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { VotingEscrow, GaugeVoter, EscrowIVotesAdapter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { Swapper } from "src/Swapper.sol";
import { ISwapper } from "src/interfaces/ISwapper.sol";
import { IRewardsDistributor } from "src/interfaces/IRewardsDistributor.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { console2 as console } from "forge-std/console2.sol";

contract AutoCompoundStrategy is Initializable, ERC721Holder, UUPSUpgradeable, DaoAuthorizable, IStrategy {
    using SafeERC20 for IERC20;

    ///@notice The bytes32 identifier for admin role functions.
    bytes32 public constant AUTOCOMPOUND_STRATEGY_ADMIN_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_ADMIN_ROLE");

    error MasterTokenAlreadySet();
    error StrategyDoesNotOwnToken();
    error OnlyVaultCanCall();
    error MasterTokenNotSet();

    /// @notice The gauge voter where this contract votes for gauges.
    GaugeVoter public voter;

    /// @notice The vault address where this contract auto-compounds(deposits kat).
    AvKATVault public vault;

    /// @notice The swapper contract which this contract asks for claiming tokens.
    Swapper public swapper;

    /// @notice The token contract that vault uses as assets.
    address public token;

    /// @notice The escrow contract
    VotingEscrow public escrow;

    /// @notice The ivotes adapter for delegation
    EscrowIVotesAdapter public ivotesAdapter;

    /// @notice The lock NFT contract
    LockNFT public lockNft;

    /// @notice The single tokenId that this strategy holds and manages
    uint256 public masterTokenId;

    /// @notice The address that this strategy delegates voting power to
    address public delegatee;

    /// @dev Ensures only the vault can call this function
    modifier onlyVault() {
        if (msg.sender != address(vault)) {
            revert OnlyVaultCanCall();
        }
        _;
    }

    /// @dev Ensures master token ID has been set
    modifier masterTokenSet() {
        if (masterTokenId == 0) {
            revert MasterTokenNotSet();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        address _swapper,
        address _vault,
        address _rewardDistributor
    )
        external
        initializer
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ERC721Holder_init();

        escrow = VotingEscrow(_escrow);
        voter = GaugeVoter(escrow.voter());
        swapper = Swapper(_swapper);
        ivotesAdapter = EscrowIVotesAdapter(escrow.ivotesAdapter());
        lockNft = LockNFT(escrow.lockNFT());

        vault = AvKATVault(_vault);
        token = vault.asset();

        // As the caller on distributor's `claim` function will be swapper,
        // it can only work if this contract allowed swapper to claim on behalf.
        IRewardsDistributor(_rewardDistributor).toggleOperator(address(this), _swapper);
    }

    /// @notice Sets the delegatee address for voting power delegation.
    /// @param _delegatee The address to delegate voting power to.
    function setDelegatee(address _delegatee) external auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) {
        delegatee = _delegatee;
        if (_delegatee != address(0)) {
            ivotesAdapter.delegate(_delegatee);
        }
    }

    /// @notice Claims and swaps token. In the end, deposits into vault the kat token
    ///         that it was either claimed or swapped into.
    /// @param _tokens Which tokens to claim.
    /// @param _amounts How much to claim for each token.
    /// @param _proofs The merkle proof that this contract holds `_amounts` on merkle distributor.
    /// @param _actions The actions that Swapper contract executes. Most times, it will be swap actions.
    /// @return Returns shares that were minted in exchange for depositting kat tokens.
    function claimAndCompound(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs,
        Action[] calldata _actions
    )
        external
        returns (uint256)
    {
        // which tokens to claim for with their proofs and amounts.
        ISwapper.Claim memory claimTokens = ISwapper.Claim(_tokens, _amounts, _proofs);

        (uint256 claimedAmount,) = swapper.claimAndSwap(claimTokens, _actions, 0);

        // If claimedAmount is greater than 0, autocompound received some amounts on `token`.
        // Donate to vault to increase totalAssets without minting shares.
        // This increases the value of all existing shares proportionally.
        if (claimedAmount > 0) {
            IERC20(token).approve(address(vault), claimedAmount);
            vault.donate(claimedAmount);
        }

        return claimedAmount;
    }

    /*//////////////////////////////////////////////////////////////
                        IStrategy Implementation
    //////////////////////////////////////////////////////////////*/

    /// @notice Handles deposit by creating lock and merging to master token.
    /// @param _amount Amount of assets to deposit.
    function handleDeposit(uint256 _amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(token).approve(address(escrow), _amount);
        uint256 tokenId = escrow.createLock(_amount);

        if (masterTokenId == 0) {
            masterTokenId = tokenId;
        } else {
            escrow.merge(tokenId, masterTokenId);
        }
    }

    /// @notice Handles deposit of existing token by merging to master token.
    /// @param tokenId The token ID to merge.
    function handleDepositToken(uint256 tokenId) external onlyVault masterTokenSet {
        // Merge the received token to master token
        escrow.merge(tokenId, masterTokenId);
    }

    /// @notice Handles withdrawal by splitting master token and transferring to receiver.
    /// @param receiver The address to receive the split token.
    /// @param assets Amount of assets to withdraw.
    function handleWithdraw(address receiver, uint256 assets) external onlyVault masterTokenSet returns (uint256) {
        // Split the master token
        uint256 newTokenId = escrow.split(masterTokenId, assets);

        // Transfer the new token to receiver
        lockNft.safeTransferFrom(address(this), receiver, newTokenId);

        return newTokenId;
    }

    /// @notice Returns the total assets managed by the strategy.
    /// @return The total amount of assets locked in the master token.
    function totalAssets() external view returns (uint256) {
        if (masterTokenId == 0) {
            return 0;
        }

        return escrow.locked(masterTokenId).amount;
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal override auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[40] private __gap;
}
