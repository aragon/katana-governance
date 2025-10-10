// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable as ERC721 } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { OwnableUpgradeable as Ownable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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

abstract contract NFTBaseStrategy is Initializable, ERC721Holder, Ownable, IStrategyNFT {
    using SafeERC20 for IERC20;

    /// @notice The ERC20 asset token.
    address internal asset;

    /// @notice The single tokenId that this strategy holds and manages
    uint256 public masterTokenId;

    /// @notice The escrow contract
    VotingEscrow public escrow;

    /// @notice The ERC721 contract.
    ERC721 public nft;

    modifier masterTokenSet() {
        if (masterTokenId == 0) revert MasterTokenNotSet();
        _;
    }

    function __NFTBaseStrategy_init(
        address _escrow,
        address _asset,
        address _nft,
        address _owner
    )
        internal
        onlyInitializing
    {
        __ERC721Holder_init();
        asset = _asset;
        escrow = VotingEscrow(_escrow);
        nft = ERC721(_nft);

        _transferOwnership(_owner);
    }

    /// @inheritdoc IStrategy
    function deposit(uint256 _amount) public virtual {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);

        _deposit(_amount);
    }

    /// @inheritdoc IStrategyNFT
    function depositTokenId(uint256 _tokenId) public virtual onlyOwner masterTokenSet {
        // Merge the received token to master token
        escrow.merge(_tokenId, masterTokenId);
    }

    /// @inheritdoc IStrategy
    function withdraw(address _receiver, uint256 _assets) public virtual onlyOwner masterTokenSet returns (uint256) {
        // Split the master token
        uint256 newTokenId = escrow.split(masterTokenId, _assets);

        // Transfer the new token to receiver
        nft.safeTransferFrom(address(this), _receiver, newTokenId);

        return newTokenId;
    }

    /// @inheritdoc IStrategyNFT
    function receiveMasterToken(uint256 _masterTokenId) public virtual onlyOwner {
        // If master token was already set, don't allow to change it.
        if (masterTokenId != 0 && masterTokenId != _masterTokenId) {
            revert MasterTokenAlreadySet();
        }

        masterTokenId = _masterTokenId;
    }

    /// @inheritdoc IStrategy
    function retireStrategy() public virtual onlyOwner {
        nft.safeTransferFrom(address(this), msg.sender, masterTokenId);
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
        IERC20(asset).approve(address(escrow), _amount);
        uint256 tokenId = escrow.createLock(_amount);

        escrow.merge(tokenId, masterTokenId);
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[46] private __gap;
}
