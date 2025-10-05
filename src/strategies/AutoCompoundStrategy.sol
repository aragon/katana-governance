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
import { IStrategyNFT } from "src/interfaces/IStrategyNFT.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";

contract AutoCompoundStrategy is Initializable, ERC721Holder, UUPSUpgradeable, DaoAuthorizable, IStrategyNFT {
    using SafeERC20 for IERC20;

    ///@notice The bytes32 identifier for admin role functions.
    bytes32 public constant AUTOCOMPOUND_STRATEGY_ADMIN_ROLE = keccak256("AUTOCOMPOUND_STRATEGY_ADMIN_ROLE");

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

    /// @notice The address that this strategy delegates voting power to.
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
        ivotesAdapter = EscrowIVotesAdapter(escrow.ivotesAdapter());
        lockNft = LockNFT(escrow.lockNFT());
        voter = GaugeVoter(escrow.voter());

        swapper = Swapper(_swapper);

        vault = AvKATVault(_vault);
        token = vault.asset();

        // As the caller on distributor's `claim` function will be swapper,
        // it can only work if this contract allowed swapper to claim on behalf.
        IRewardsDistributor(_rewardDistributor).toggleOperator(address(this), _swapper);
    }

    /// @notice Sets the delegatee address for voting power delegation.
    /// @param _delegatee The address to delegate voting power to.
    function delegate(address _delegatee) public virtual auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) {
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
        public
        virtual
        returns (uint256)
    {
        // which tokens to claim for with their proofs and amounts.
        ISwapper.Claim memory claimTokens = ISwapper.Claim(_tokens, _amounts, _proofs);

        (uint256 claimedAmount,) = swapper.claimAndSwap(claimTokens, _actions, 0);

        // If claimedAmount is greater than 0, autocompound received some amounts on `token`.
        // Donate to vault to increase totalAssets without minting shares.
        // This increases the value of all existing shares proportionally.
        if (claimedAmount > 0) {
            _deposit(claimedAmount);
            // IERC20(token).approve(address(vault), claimedAmount);
            // vault.donate(claimedAmount);
        }

        return claimedAmount;
    }

    /// @notice Votes on gauge voter with `_votes`.
    /// @dev The caller must invoke `delegate` with this strategy’s address, effectively delegating to itself.
    /// @param _votes The gauges and their weights to vote for.
    function vote(GaugeVoter.GaugeVote[] calldata _votes) external virtual auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) {
        voter.vote(_votes);
    }

    /*//////////////////////////////////////////////////////////////
                        IStrategyNFT Implementation
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStrategy
    function deposit(uint256 _amount) public virtual {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

        _deposit(_amount);
    }

    /// @inheritdoc IStrategyNFT
    function depositTokenId(uint256 _tokenId) public virtual onlyVault masterTokenSet {
        // Merge the received token to master token
        escrow.merge(_tokenId, masterTokenId);
    }

    /// @inheritdoc IStrategy
    function withdraw(address _receiver, uint256 _assets) public virtual onlyVault masterTokenSet returns (uint256) {
        // Split the master token
        uint256 newTokenId = escrow.split(masterTokenId, _assets);

        // Transfer the new token to receiver
        lockNft.safeTransferFrom(address(this), _receiver, newTokenId);

        return newTokenId;
    }

    /// @inheritdoc IStrategyNFT
    function receiveMasterToken(uint256 _masterTokenId) public virtual onlyVault {
        masterTokenId = _masterTokenId;
    }

    /// @inheritdoc IStrategy
    function retireStrategy() public virtual onlyVault {
        // For safety reasons, revoke current delegatee
        ivotesAdapter.delegate(address(0));

        lockNft.safeTransferFrom(address(this), address(vault), masterTokenId);
    }

    /// @notice Returns the total assets managed by the strategy.
    /// @return The total amount of assets locked in the master token.
    function totalAssets() public view virtual returns (uint256) {
        if (masterTokenId == 0) {
            return 0;
        }

        return escrow.locked(masterTokenId).amount;
    }

    /*//////////////////////////////////////////////////////////////
                        Internal/Private
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a lock and merges it into master.
    function _deposit(uint256 _amount) internal virtual {
        IERC20(token).approve(address(escrow), _amount);
        uint256 tokenId = escrow.createLock(_amount);

        escrow.merge(tokenId, masterTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                        Upgrade
    //////////////////////////////////////////////////////////////*/
    function _authorizeUpgrade(address) internal virtual override auth(AUTOCOMPOUND_STRATEGY_ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[41] private __gap;
}
