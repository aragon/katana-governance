// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import { VotingEscrow, EscrowIVotesAdapter, GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC7540 } from "./abstracts/ERC7540.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { AutoCompoundStrategy } from "./AutoCompoundStrategy.sol";

contract AvKATVault is ERC7540, Initializable, DaoAuthorizable {
    using FixedPointMathLib for uint256;

    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    struct ClaimableRequests {
        RedemptionRequest[] requests;
        uint256[] foundIndices;
        uint256 cumulativeShares;
        uint256 cumulativeAssets;
    }

    /// Addresses required for operations.
    EscrowIVotesAdapter public ivotesAdapter;
    VotingEscrow public escrow;
    LockNFT public lockNft;
    address public strategy;

    /// The single tokenId that this vault will hold and
    /// will contain all users' token ids accumulated.
    uint256 public masterTokenId;

    error MasterTokenNotSet();
    error TokenNotOwned();

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
    }

    /// @dev Deposit/Withdraws can only occur if masterTokenId is set.
    ///      As long as `initialize` is called, masterTokenId gets set.
    modifier masterTokenSet() {
        if (masterTokenId == 0) {
            revert MasterTokenNotSet();
        }

        _;
    }

    /// @dev To create master tokenId, another party must transfer
    ///      the existing tokenId to this contract and then `initialize`
    ///      must be called.
    function initialize(uint256 _tokenId) external initializer {
        address owner = lockNft.ownerOf(_tokenId);
        if (owner != address(this)) {
            revert TokenNotOwned();
        }

        masterTokenId = _tokenId;
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
        uint256 _shares,
        address _controller,
        address _owner
    )
        public
        virtual
        override
        masterTokenSet
        returns (uint256)
    {
        RedemptionRequest[] storage requests = _pendingRedemption[_controller];

        // Allow up to `MAX_REQUESTS` at the same time. Once redeemed, the list
        // of requests decreases, allowing user to request more.
        if (requests.length > MAX_REQUESTS) {
            revert TooManyRequests();
        }

        // Take owner's shares back.
        transferFrom(_owner, address(this), _shares);

        uint256 assets = convertToAssets(_shares);

        // Splits `masterTokenId` into `newTokenId` with amounts:
        // masterTokenId => reduced by `assets`.
        // newTokenId => assets
        uint256 newTokenId = escrow.split(masterTokenId, assets);

        requests.push(
            RedemptionRequest({
                assets: assets,
                shares: _shares,
                tokenId: newTokenId,
                // TODO: add the time after which it can be withdrawn.(use queue)
                claimableTimestamp: uint32(block.timestamp) + uint32(escrow.locked(newTokenId).start)
            })
        );

        _totalPendingRedeemAssets += assets;

        // start a withdrawal process.
        escrow.beginWithdrawal(newTokenId);

        emit RedeemRequest(_controller, _owner, REQUEST_ID, msg.sender, _shares);

        return REQUEST_ID;
    }

    function pendingRedeemRequest(uint256, address _controller) public view returns (uint256) {
        return _aggregate(_controller, _getPendingShares);
    }

    function claimableRedeemRequest(uint256, address _controller) public view returns (uint256) {
        return _aggregate(_controller, _getClaimableShares);
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
        masterTokenSet
        controllerAllowed(_controller)
        returns (uint256 assets)
    {
        if (_shares == 0) {
            revert ZeroAmount();
        }

        ClaimableRequests memory claimable = getRedeemableRequestsUpTo(_shares, _controller);

        uint256 len = claimable.requests.length;
        if (len == 0) {
            revert NotClaimableYet();
        }

        RedemptionRequest[] storage allRequests = _pendingRedemption[_controller];

        _totalPendingRedeemAssets -= claimable.cumulativeAssets;

        // Process all requests that are claimable and
        // clear these requests from storage array.
        for (uint256 i = 0; i < len; i++) {
            RedemptionRequest memory request = claimable.requests[i];

            // This transfers back assets from escrow to this contract.
            escrow.withdraw(request.tokenId);

            // remove the request from the storage array as we already processed it.
            allRequests[claimable.foundIndices[i]] = allRequests[allRequests.length - 1];
            allRequests.pop();
        }

        // burns `cumulativeShares` and transfers `cumulativeAssets` back to user.
        _withdraw(msg.sender, _receiver, _controller, claimable.cumulativeAssets, claimable.cumulativeShares);

        return claimable.cumulativeAssets;
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _controller
    )
        public
        virtual
        override
        masterTokenSet
        controllerAllowed(_controller)
        returns (uint256 shares)
    {
        if (_assets == 0) {
            revert ZeroAmount();
        }

        ClaimableRequests memory claimable = getWithdrawableRequestsUpTo(_assets, _controller);

        uint256 len = claimable.requests.length;
        if (len == 0) {
            revert NotClaimableYet();
        }

        RedemptionRequest[] storage allRequests = _pendingRedemption[_controller];

        _totalPendingRedeemAssets -= claimable.cumulativeAssets;

        // Process all requests that are claimable and
        // clear these requests from storage array.
        for (uint256 i = 0; i < len; i++) {
            RedemptionRequest memory request = claimable.requests[i];

            // This transfers back assets from escrow to this contract.
            escrow.withdraw(request.tokenId);

            // remove the request from the storage array as we already processed it.
            allRequests[claimable.foundIndices[i]] = allRequests[allRequests.length - 1];
            allRequests.pop();
        }

        // burns `cumulativeShares` and transfers `cumulativeAssets` back to user.
        _withdraw(msg.sender, _receiver, _controller, claimable.cumulativeAssets, claimable.cumulativeShares);

        return claimable.cumulativeShares;
    }

    /// @dev Transfer `assets` from caller to Vault.
    ///      User must have approved `Vault` for this.
    function deposit(uint256 assets, address receiver) public virtual override masterTokenSet returns (uint256) {
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
    function depositToken(uint256 tokenId, address receiver) public virtual masterTokenSet returns (uint256) {
        uint256 assets = escrow.locked(tokenId).amount;

        // If user doesn't hold veNFT, this will fail.
        lockNft.transferFrom(msg.sender, address(this), tokenId);

        escrow.merge(tokenId, masterTokenId);

        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function maxWithdraw(address _controller) public view virtual override returns (uint256) {
        return _aggregate(_controller, _getClaimableAssets);
    }

    function maxRedeem(address _controller) public view virtual override returns (uint256) {
        return _aggregate(_controller, _getClaimableShares);
    }

    // Preview functions always revert for async flows
    function previewWithdraw(uint256) public pure virtual override returns (uint256) {
        revert NotAsyncable();
    }

    function previewRedeem(uint256) public pure virtual override returns (uint256) {
        revert NotAsyncable();
    }

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Public Functions
    //////////////////////////////////////////////////////////////*/

    // Public functions
    function getRedeemableRequestsUpTo(
        uint256 _shares,
        address _controller
    )
        public
        view
        returns (ClaimableRequests memory result)
    {
        return _getClaimableRequestsUpTo(_shares, _controller, _getShares);
    }

    function getWithdrawableRequestsUpTo(
        uint256 _assets,
        address _controller
    )
        public
        view
        returns (ClaimableRequests memory result)
    {
        return _getClaimableRequestsUpTo(_assets, _controller, _getAssets);
    }

    /// @notice The total pending assets that has been requested but not yet redeemed.
    function totalPendingRedeemAssets() public view returns (uint256) {
        return _totalPendingRedeemAssets;
    }

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Internal/Private Functions
    //////////////////////////////////////////////////////////////*/

    function _getClaimableRequestsUpTo(
        uint256 _amount,
        address _controller,
        function(RedemptionRequest memory) internal pure returns (uint256) _getAmount
    )
        private
        view
        returns (ClaimableRequests memory result)
    {
        RedemptionRequest[] storage requests = _pendingRedemption[_controller];

        uint256 len = requests.length;
        result.requests = new RedemptionRequest[](len);
        result.foundIndices = new uint256[](len);

        uint256 count;
        uint256 cumulative;

        for (uint256 i = 0; i < len; i++) {
            RedemptionRequest memory request = requests[i];

            if (request.claimableTimestamp > block.timestamp) {
                continue;
            }

            uint256 requestAmount = _getAmount(request);

            if (cumulative + requestAmount <= _amount) {
                result.requests[count] = request;
                result.foundIndices[count] = i;
                result.cumulativeShares += request.shares;
                result.cumulativeAssets += request.assets;

                cumulative += requestAmount;
                count++;
            }
        }

        // Resize arrays to actual count
        assembly {
            mstore(mload(result), count) // result.requests.length = count
            mstore(mload(add(result, 0x20)), count) // result.indices.length = count
        }
    }

    function _aggregate(
        address _controller,
        function(RedemptionRequest memory) internal view returns (uint256) _getValue
    )
        private
        view
        returns (uint256)
    {
        RedemptionRequest[] memory requests = _pendingRedemption[_controller];

        uint256 total;
        for (uint256 i = 0; i < requests.length; i++) {
            total += _getValue(requests[i]);
        }

        return total;
    }

    function _getPendingShares(RedemptionRequest memory request) private view returns (uint256) {
        return request.claimableTimestamp > block.timestamp ? request.shares : 0;
    }

    function _getClaimableShares(RedemptionRequest memory request) private view returns (uint256) {
        return request.claimableTimestamp <= block.timestamp ? request.shares : 0;
    }

    function _getClaimableAssets(RedemptionRequest memory request) private view returns (uint256) {
        return request.claimableTimestamp <= block.timestamp ? request.assets : 0;
    }

    function _getShares(RedemptionRequest memory request) private pure returns (uint256) {
        return request.shares;
    }

    function _getAssets(RedemptionRequest memory request) private pure returns (uint256) {
        return request.assets;
    }

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
