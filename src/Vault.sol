// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { VotingEscrow, EscrowIVotesAdapter, GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC7540 } from "./abstracts/ERC7540.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { CompoundStrategy } from "./CompoundStrategy.sol";

contract AvKATVault is ERC7540, DaoAuthorizable {
    using FixedPointMathLib for uint256;

    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /// Addresses required for operations.
    EscrowIVotesAdapter public ivotesAdapter;
    VotingEscrow public escrow;
    LockNFT public lockNft;
    address public strategy;

    /// The single tokenId that this vault will hold and
    /// will contain all users' token ids accumulated.
    uint256 public masterTokenId;

    constructor(
        address _dao,
        address _ivotesAdapter,
        address _strategy,
        address _asset,
        string memory _name,
        string memory _symbol
    )
        ERC7540(_asset, _name, _symbol)
        DaoAuthorizable(IDAO(_dao))
    {
        ivotesAdapter = EscrowIVotesAdapter(_ivotesAdapter);
        escrow = VotingEscrow(ivotesAdapter.escrow());
        lockNft = LockNFT(escrow.lockNFT());

        if (_strategy != address(0)) {
            _setStrategy(_strategy);
        }

        masterTokenId = escrow.createLock(1e18);
    }

    function setStrategy(address _strategy) public auth(VAULT_ADMIN_ROLE) {
        _setStrategy(_strategy);
    }

    /// @dev As Vault allows to deposit already created tokenId locks,
    ///      this means that actual amount of assets can not be depositted
    ///      in vault(it says in escrow), hence using the basic `totalAssets`
    ///      implementation, such as from OZ will not reflect the correct
    ///      depositted amounts.
    function totalAssets() public view virtual override returns (uint256) {
        return escrow.locked(masterTokenId).amount - _totalPendingRedeemAssets;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        virtual
        override
        returns (uint256 requestId)
    {
        // Take `owner`'s shares back.
        SafeERC20.safeTransferFrom(IERC20(asset()), owner, address(this), shares);

        uint256 assets = convertToAssets(shares);

        // Split splits `masterTokenId` into `newTokenId` with amounts such as:
        // masterTokenId => current masterTokenId ammount - assets
        // newTokenId => assets
        uint256 newTokenId = escrow.split(masterTokenId, assets);

        _pendingRedemption[controller] = RedemptionRequest({
            assets: assets,
            shares: shares,
            tokenId: newTokenId,
            // TODO: add the time after which it can be withdrawn.(use queue)
            claimableTimestamp: uint32(block.timestamp) + uint32(escrow.locked(newTokenId).start)
        });

        _totalPendingRedeemAssets += assets;

        // masterTokenId now contains its total amount - assets
        // start a withdrawal process.
        escrow.beginWithdrawal(newTokenId);

        emit RedeemRequest(controller, owner, REQUEST_ID, msg.sender, shares);
    }

    function pendingRedeemRequest(uint256, address controller) public view returns (uint256 pendingShares) {
        RedemptionRequest memory request = _pendingRedemption[controller];

        if (request.claimableTimestamp > block.timestamp) {
            return request.shares;
        }

        return 0;
    }

    function claimableRedeemRequest(uint256, address controller) public view returns (uint256 claimableShares) {
        RedemptionRequest memory request = _pendingRedemption[controller];
        if (request.claimableTimestamp <= block.timestamp && request.shares > 0) {
            return request.shares;
        }

        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    function redeem(
        uint256 _shares,
        address _receiver,
        address _controller
    )
        public
        virtual
        override
        controllerAllowed(_controller)
        returns (uint256 assets)
    {
        if (_shares == 0) {
            revert ZeroAmount();
        }

        RedemptionRequest storage request = _pendingRedemption[_controller];

        if (block.timestamp > request.claimableTimestamp) {
            revert NotClaimableYet();
        }

        // Ensure that we use the same ratio as at the time of making this request in requestRedeem.
        // This is because during requestRedeem and redeem, share price per asset could change.
        assets = _shares.mulDivDown(request.assets, request.shares);
        uint256 assetsUp = _shares.mulDivUp(request.assets, request.shares);

        request.assets = request.assets > assetsUp ? request.assets - assetsUp : 0;
        request.shares -= _shares;

        _totalPendingRedeemAssets -= assets;

        // This transfers back amount to this contract
        escrow.withdraw(request.tokenId);

        // transfer back the assets to the user.
        SafeERC20.safeTransferFrom(IERC20(asset()), address(this), _receiver, assets);

        emit Withdraw(msg.sender, _receiver, _controller, assets, _shares);
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override
        controllerAllowed(_controller)
        returns (uint256 shares)
    {
        RedemptionRequest storage request = _pendingRedemption[_controller];
        if (block.timestamp > request.claimableTimestamp) {
            revert NotClaimableYet();
        }

        // Claiming partially introduces precision loss. The user therefore
        // receives a rounded down amount, while the claimable balance is
        // reduced by a rounded up amount.
        shares = _assets.mulDivDown(request.shares, request.assets);
        uint256 sharesUp = _assets.mulDivUp(request.shares, request.assets);

        request.assets -= _assets;
        request.shares = request.shares > sharesUp ? request.shares - sharesUp : 0;

        _totalPendingRedeemAssets -= _assets;

        // This transfers back amount to this contract
        escrow.withdraw(request.tokenId);

        emit Withdraw(msg.sender, _receiver, _controller, _assets, shares);

        // transfer back the assets to the user.
        SafeERC20.safeTransferFrom(IERC20(asset()), address(this), _receiver, _assets);

        emit Withdraw(msg.sender, _receiver, _controller, _assets, shares);
    }

    /// @dev Transfer `assets` from caller to Vault.
    ///      User must have approved `Vault` for this.
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        // Transfers `assets` from caller to this vault
        // and mints shares as well.
        super.deposit(assets, receiver);

        // creates a lock which transfers assets to escrow.
        uint256 tokenId = escrow.createLock(assets);

        // merge newly created token to Vault's
        // single tokenid for accumulation.
        escrow.merge(tokenId, masterTokenId);
    }

    /// @dev If `tokenId` position is already created on escrow,
    ///      this allows to still deposit which will mint the shares
    ///      depending on the amount that tokenId lock was created on escrow.
    function depositToken(uint256 tokenId, address receiver) public virtual returns (uint256) {
        uint256 assets = escrow.locked(tokenId).amount;

        lockNft.transferFrom(msg.sender, address(this), tokenId);
        escrow.merge(tokenId, masterTokenId);

        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function maxWithdraw(address _controller) public view virtual override returns (uint256) {
        RedemptionRequest memory request = _pendingRedemption[_controller];
        if (request.claimableTimestamp <= block.timestamp) {
            return request.assets;
        }

        return 0;
    }

    function maxRedeem(address _controller) public view virtual override returns (uint256) {
        RedemptionRequest memory request = _pendingRedemption[_controller];
        if (request.claimableTimestamp <= block.timestamp) {
            return request.shares;
        }

        return 0;
    }

    // Preview functions always revert for async flows
    function previewWithdraw(uint256) public pure virtual override returns (uint256) {
        revert NotAsyncable();
    }

    function previewRedeem(uint256) public pure virtual override returns (uint256) {
        revert NotAsyncable();
    }

    /*//////////////////////////////////////////////////////////////
                       Helper Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Allows an admin to set a new strategy contract.
    ///      It automatically undelegates from old strategy
    ///      and delegates to new one.
    function _setStrategy(address _strategy) public auth(VAULT_ADMIN_ROLE) {
        // Since Vault only holds `masterTokenId`, the delegate
        // will delegate that token to new strategy.
        ivotesAdapter.delegate(_strategy);

        // approve strategy contract for nft operations.
        // needed so strategy can call `merge` as an approved owner.
        lockNft.setApprovalForAll(_strategy, true);

        strategy = _strategy;
    }
}
