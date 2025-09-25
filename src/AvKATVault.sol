// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC4626Upgradeable as ERC4626 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { VotingEscrow, EscrowIVotesAdapter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract AvKATVault is Initializable, ERC721Holder, ERC4626, UUPSUpgradeable, DaoAuthorizable {
    /// @notice bytes32 identifier for admin role functions.
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /// @notice bytes32 identifier of sweeper that can withdraw mistakenly depositted funds.
    bytes32 public constant SWEEPER_ROLE = keccak256("SWEEPER_ROLE");

    /// @notice The ivotes adapter, responsible for delegation activities.
    EscrowIVotesAdapter public ivotesAdapter;

    /// @notice The escrow contract address.
    VotingEscrow public escrow;

    /// @notice The nft contract that escrow mints in exchange of erc20 tokens.
    LockNFT public lockNft;

    /// @notice The strategy contract that vault delegates its vp.
    address public strategy;

    /// The single tokenId that this vault will hold and
    /// will contain all users' token ids accumulated.
    uint256 public masterTokenId;

    event StrategySet(address strategy);
    event Sweep(uint256 tokenId, address receiver);
    event TokenIdWithdrawn(uint256 tokenId, address receiver);

    error MasterTokenNotSet();
    error CannotTransferMasterToken();
    error TokenNotOwned();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        address _strategy,
        address _asset,
        string memory _name,
        string memory _symbol
    )
        external
        reinitializer(1)
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));

        escrow = VotingEscrow(_escrow);
        ivotesAdapter = EscrowIVotesAdapter(escrow.ivotesAdapter());
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
    ///      must be called. This is needed as at the deployment time,
    ///      we might not have caller to have the lock position already
    ///      created on escrow, so it can be done at a later time.
    function initializeMasterTokenId(uint256 _tokenId) external reinitializer(2) {
        address owner = lockNft.ownerOf(_tokenId);
        if (owner != address(this)) {
            revert TokenNotOwned();
        }

        masterTokenId = _tokenId;

        // After initialize is called, totalAssets() will reflect the amount
        // of `masterTokenId`, but totalSupply will be 0 and the first depositor
        // will get 0 shares unless provided deposit is not big enough to cause
        // shares > 0. To avoid consistency issues, we mint the according shares
        // to address(1) to increase total supply.
        _mint(address(1), escrow.locked(_tokenId).amount);
    }

    /// @notice Allows to change a strategy contract.
    /// @param _strategy The new strategy contract.
    function setStrategy(address _strategy) public auth(VAULT_ADMIN_ROLE) {
        _setStrategy(_strategy);
    }

    /// @dev As Vault allows to deposit already created tokenId locks,
    ///      this means that actual amount of assets can not be depositted
    ///      in vault(it says in escrow), hence using the basic `totalAssets`
    ///      implementation, such as from OZ will not reflect the correct
    ///      depositted amounts.
    function totalAssets() public view virtual override returns (uint256) {
        return escrow.locked(masterTokenId).amount;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    )
        internal
        virtual
        override
        masterTokenSet
    {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        _burn(_owner, _shares);
        uint256 newTokenId = escrow.split(masterTokenId, _assets);
        lockNft.transferFrom(address(this), _receiver, newTokenId);

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);

        emit TokenIdWithdrawn(newTokenId, _receiver);
    }

    /// @dev Transfer `assets` from caller to Vault.
    ///      User must have approved `Vault` for this.
    function _deposit(
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares
    )
        internal
        virtual
        override
        masterTokenSet
    {
        super._deposit(_caller, _receiver, _assets, _shares);

        IERC20(asset()).approve(address(escrow), _assets);

        // creates a lock which transfers assets to escrow.
        uint256 tokenId = escrow.createLock(_assets);

        // merge newly created token to Vault's
        // single tokenid for accumulation.
        escrow.merge(tokenId, masterTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev If `tokenId` position is already created on escrow,
    ///      this allows to still deposit which will mint the shares
    ///      depending on the amount that tokenId lock was created on escrow.
    function depositToken(uint256 _tokenId, address _receiver) public virtual masterTokenSet returns (uint256) {
        uint256 assets = escrow.locked(_tokenId).amount;

        require(assets <= maxDeposit(_receiver), "ERC4626: deposit more than max");
        uint256 shares = previewDeposit(assets);

        // Reverts if the caller does not own a veNFT.
        // Safe transfer is unnecessary since `_receiver` is always this contract,
        // which we know can correctly forward tokens to users (see `_withdraw`).
        // If `amount` on tokenId is 0, either merge or withdrawal occured in which case
        // `transferFrom` will anyways fail.
        lockNft.transferFrom(msg.sender, address(this), _tokenId);

        escrow.merge(_tokenId, masterTokenId);

        _mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, assets, shares);

        return shares;
    }

    /// @notice send veNFT mistakenly transferred to `_receiver`.
    /// @dev If veNFT was depositted through `depositToken`, it would
    ///      be merged, hence such veNFTs can not be recovered.
    function recoverNFT(uint256 _tokenId, address _receiver) external auth(SWEEPER_ROLE) {
        if (_tokenId == masterTokenId) {
            revert CannotTransferMasterToken();
        }

        lockNft.safeTransferFrom(address(this), _receiver, _tokenId);

        emit Sweep(_tokenId, _receiver);
    }

    /// @dev Allows an admin to set a new strategy contract.
    ///      It automatically undelegates from old strategy
    ///      and delegates to new one.
    function _setStrategy(address _strategy) internal virtual {
        // Since Vault only holds `masterTokenId`, the delegate
        // will delegate that token to new strategy.
        ivotesAdapter.delegate(_strategy);

        // approve strategy contract for nft operations.
        // needed so strategy can call `merge` as an approved owner.
        lockNft.setApprovalForAll(_strategy, true);

        strategy = _strategy;

        emit StrategySet(_strategy);
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal override auth(VAULT_ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[45] private __gap;
}
