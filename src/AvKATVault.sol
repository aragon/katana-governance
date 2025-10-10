// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC4626Upgradeable as ERC4626 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable as Pausable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import { SafeERC20Upgradeable as SafeERC20 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { VotingEscrow, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import { IStrategyNFT as IStrategy } from "src/interfaces/IStrategyNFT.sol";
import { IVaultNFT } from "src/interfaces/IVaultNFT.sol";

contract AvKATVault is Initializable, ERC721Holder, Pausable, ERC4626, UUPSUpgradeable, IVaultNFT, DaoAuthorizable {
    using SafeERC20 for IERC20;

    /// @notice bytes32 identifier for admin role functions.
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /// @notice bytes32 identifier of sweeper that can withdraw mistakenly depositted funds.
    bytes32 public constant SWEEPER_ROLE = keccak256("SWEEPER_ROLE");

    /// @notice The escrow contract address.
    VotingEscrow public escrow;

    /// @notice The nft contract that escrow mints in exchange of erc20 tokens.
    LockNFT public lockNft;

    /// @notice The strategy contract that holds the master token and handles escrow operations.
    IStrategy public strategy;

    /// The single tokenId that this vault will hold and
    /// will contain all users' token ids accumulated.
    uint256 public masterTokenId;

    error StrategyNotSet();
    error MasterTokenNotSet();
    error SameStrategyNotAllowed();
    error MinMasterTokenInitAmountTooLow();

    event StrategySet(address strategy);
    event AssetsDonated(uint256 assets);

    modifier whenStrategySet() {
        if (address(strategy) == address(0)) revert StrategyNotSet();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @param _dao The dao address.
    /// @param _escrow The escrow contract providing the asset and NFT tokens.
    /// @param _name The name of the share token minted by this vault.
    /// @param _symbol The symbol of the share token minted by this vault.
    function initialize(
        address _dao,
        address _escrow,
        string memory _name,
        string memory _symbol
    )
        external
        initializer
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ERC20_init(_name, _symbol);

        escrow = VotingEscrow(_escrow);

        __ERC4626_init(IERC20(escrow.token()));

        lockNft = LockNFT(escrow.lockNFT());

        // Always start with paused state to ensure that deposits/withdrawals can not occur.
        // Once `initializeMasterTokenAndStrategy` is called(which fills in vault), it's safer
        // to unpause at that point to avoid loses with inflation attack situations.
        _pause();
    }

    /// @notice Pauses the contract, disallowing deposits/withdrawals.
    function pause() external auth(VAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract, allowing deposits/withdrawals.
    function unpause() external auth(VAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IVaultNFT
    /// @dev To set up the master tokenId, an existing tokenId must be
    ///      transferred here and `initialize` called. This allows creation
    ///      to happen later if no lock existed at deployment.
    function initializeMasterTokenAndStrategy(
        uint256 _tokenId,
        address _strategy
    )
        public
        virtual
        auth(VAULT_ADMIN_ROLE)
    {
        if (_tokenId == 0) revert TokenIdCannotBeZero();
        if (masterTokenId != 0) revert MasterTokenAlreadySet();

        // mint according shares to sender.
        uint256 assetAmount = _getTokenIdAmount(_tokenId);
        if (assetAmount < minMasterTokenInitAmount()) {
            revert MinMasterTokenInitAmountTooLow();
        }

        lockNft.safeTransferFrom(msg.sender, address(this), _tokenId);
        _mint(msg.sender, convertToShares(assetAmount));

        masterTokenId = _tokenId;

        if (address(_strategy) != address(0)) {
            _setStrategy(_strategy);
        }
    }

    /// @notice Allows to change a strategy contract.
    /// @param _strategy The new strategy contract.
    function setStrategy(address _strategy) public auth(VAULT_ADMIN_ROLE) {
        _setStrategy(_strategy);
    }

    // strategy is not set
    // giorgi deposits 30
    // alice deposits 50

    // strategy got set
    // 80 was created into master token id

    // bob transfers directly to vault 40
    // strategy got set to address(0)

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev If a strategy is active, it is responsible for holding the assets
    ///      and reporting totalAssets. Otherwise, if a masterTokenId exists,
    ///      retrieve the total balance associated with it from the escrow.
    function totalAssets() public view virtual override returns (uint256) {
        uint256 totalAssets_ = super.totalAssets();

        if (address(strategy) != address(0)) {
            return strategy.totalAssets() + totalAssets_;
        }

        // If strategy is not set:
        //     if masterTokenId is not initialized, return balance of vault directly.
        //     if masterTokenId is initialized, return its locked amount + if there's any balance on vault.
        if (masterTokenId == 0) return totalAssets_;

        return _getTokenIdAmount(masterTokenId) + totalAssets_;
    }

    /// @notice Transfer `assets` from caller to Vault, then to Strategy.
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
        whenNotPaused
    {
        super._deposit(_caller, _receiver, _assets, _shares);

        if (address(strategy) != address(0)) {
            // Approve strategy so it can transfer `_assets`.
            IERC20(asset()).approve(address(strategy), _assets);

            // Strategy handles createLock and merge to masterTokenId
            strategy.deposit(_assets);
        }
    }

    /// @notice Overrides withdraw function from ERC4626 to allow
    ///         custom logic through strategy.
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
        whenNotPaused
    {
        _withdrawWithTokenId(_caller, _receiver, _owner, _assets, _shares);
    }

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultNFT
    /// @dev Allows deposits even if `_tokenId` is already created in the escrow.
    ///      Shares are minted based on the amount locked for that tokenId in the escrow.
    function depositTokenId(
        uint256 _tokenId,
        address _receiver
    )
        public
        virtual
        whenNotPaused
        whenStrategySet
        returns (uint256)
    {
        address sender = _msgSender();
        uint256 assets = _getTokenIdAmount(_tokenId);

        require(assets <= maxDeposit(_receiver), "ERC4626: deposit more than max");
        uint256 shares = previewDeposit(assets);

        // Transfer NFT directly to strategy (not vault)
        // Reverts if the caller does not own a veNFT.
        // If `amount` on tokenId is 0, either merge or withdrawal occurred in which case
        // `transferFrom` will anyways fail.
        lockNft.transferFrom(sender, address(strategy), _tokenId);

        // Strategy handles merge to masterTokenId
        strategy.depositTokenId(_tokenId);

        _mint(_receiver, shares);

        emit Deposit(sender, _receiver, assets, shares);
        emit TokenIdDepositted(_tokenId, sender);

        return shares;
    }

    /// @inheritdoc IVaultNFT
    function withdrawTokenId(
        uint256 _assets,
        address _receiver,
        address _owner
    )
        public
        virtual
        whenNotPaused
        whenStrategySet
        returns (uint256 tokenId)
    {
        uint256 shares = previewWithdraw(_assets);
        return _withdrawWithTokenId(_msgSender(), _receiver, _owner, _assets, shares);
    }

    /// @dev Core withdraw logic that both `_withdraw` and `withdrawTokenId` rely on.
    function _withdrawWithTokenId(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    )
        internal
        returns (uint256 tokenId)
    {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        _burn(_owner, _shares);

        if (address(strategy) != address(0)) {
            // Strategy handles split and transfer to receiver
            tokenId = strategy.withdraw(_receiver, _assets);

            emit TokenIdWithdrawn(tokenId, _receiver);
        } else {
            SafeERC20.safeTransfer(IERC20(asset()), _receiver, _assets);
        }

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /// @notice Allows to donate the assets only without minting shares.
    ///         This increases assets causing each share to cost more.
    /// @param _assets How much to donate.
    function donate(uint256 _assets) public virtual {
        SafeERC20.safeTransferFrom(IERC20(asset()), _msgSender(), address(this), _assets);

        if (address(strategy) != address(0)) {
            // Approve strategy so it can transfer `_assets`.
            IERC20(asset()).approve(address(strategy), _assets);

            // Strategy handles createLock and merge to masterTokenId
            strategy.deposit(_assets);
        }

        emit AssetsDonated(_assets);
    }

    /// @inheritdoc IVaultNFT
    function recoverNFT(uint256 _tokenId, address _receiver) external virtual auth(SWEEPER_ROLE) {
        if (_tokenId == masterTokenId) {
            revert CannotTransferMasterToken();
        }

        lockNft.safeTransferFrom(address(this), _receiver, _tokenId);

        emit Sweep(_tokenId, _receiver);
    }

    /// @inheritdoc IVaultNFT
    function minMasterTokenInitAmount() public view virtual returns (uint256) {
        return 1e6;
    }

    /// @dev Allows an admin to set a new strategy contract.
    ///      Note: The strategy now holds the master token, not the vault.
    function _setStrategy(address _strategy) internal virtual {
        address currentStrategy = address(strategy);
        if (currentStrategy == _strategy) {
            revert SameStrategyNotAllowed();
        }

        strategy = IStrategy(_strategy);

        // If the strategy was set, retire it and get masterTokenId back.
        if (currentStrategy != address(0)) {
            IStrategy(currentStrategy).retireStrategy();
        }

        // Send masterTokenId to the new strategy.
        if (_strategy != address(0)) {
            // strategy can only be set if master token was already initialized.
            if (masterTokenId == 0) revert MasterTokenNotSet();

            _sendMasterTokenToStrategy();
        }

        emit StrategySet(_strategy);
    }

    /// @notice Sends master token to strategy.
    /// @dev Caller's responsibility to ensure that `strategy` and masterTokenId are both set.
    function _sendMasterTokenToStrategy() internal virtual {
        // transfer masterTokenId to new strategy
        lockNft.safeTransferFrom(address(this), address(strategy), masterTokenId);

        // let new strategy what the master token id is
        strategy.receiveMasterToken(masterTokenId);

        // If there's any assets on vault, transfer it also to strategy.
        uint256 totalAssets_ = super.totalAssets();
        if (totalAssets_ != 0) {
            // Approve strategy so it can transfer `_assets`.
            IERC20(asset()).approve(address(strategy), totalAssets_);

            strategy.deposit(totalAssets_);
        }
    }

    /// @notice Returns the amount of ERC20 tokens locked in the escrow for a given token ID.
    /// @dev The current implementation fetches this information from `escrow`, but can be overridden if needed.
    /// @param _tokenId The token ID whose locked token balance is being retrieved.
    function _getTokenIdAmount(uint256 _tokenId) internal view virtual returns (uint256) {
        return escrow.locked(_tokenId).amount;
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal virtual override auth(VAULT_ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[46] private __gap;
}
