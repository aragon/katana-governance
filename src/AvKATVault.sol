// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC4626Upgradeable as ERC4626 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { SafeERC20Upgradeable as SafeERC20 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { VotingEscrow, EscrowIVotesAdapter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import { IStrategy } from "src/interfaces/IStrategy.sol";

contract AvKATVault is Initializable, ERC721Holder, ERC4626, UUPSUpgradeable, DaoAuthorizable {
    using SafeERC20 for IERC20;

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

    /// @notice The strategy contract that holds the master token and handles escrow operations.
    IStrategy public strategy;

    event StrategySet(address strategy);
    event Sweep(uint256 tokenId, address receiver);
    event TokenIdWithdrawn(uint256 tokenId, address receiver);

    error CannotTransferMasterToken();
    error TokenNotOwned();
    error StrategyNotSet();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _escrow,
        address _strategy,
        string memory _name,
        string memory _symbol
    )
        external
        reinitializer(1)
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ERC20_init(_name, _symbol);

        escrow = VotingEscrow(_escrow);

        __ERC4626_init(IERC20(escrow.token()));

        ivotesAdapter = EscrowIVotesAdapter(escrow.ivotesAdapter());
        lockNft = LockNFT(escrow.lockNFT());

        if (_strategy != address(0)) {
            _setStrategy(_strategy);
        }
    }

    /// @dev Deposit/Withdraws can only occur if strategy is set.
    modifier strategySet() {
        if (address(strategy) == address(0)) {
            revert StrategyNotSet();
        }

        _;
    }

    function initVault() public reinitializer(2) {
        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ == 0) {
            revert("fuck off");
        }

        _mint(address(this), totalAssets_);
    }

    /// @notice Allows to change a strategy contract.
    /// @param _strategy The new strategy contract.
    function setStrategy(address _strategy) public auth(VAULT_ADMIN_ROLE) {
        _setStrategy(_strategy);
    }

    /// @dev As Vault allows to deposit already created tokenId locks,
    ///      this means that actual amount of assets can not be depositted
    ///      in vault(it stays in escrow), hence using the basic `totalAssets`
    ///      implementation, such as from OZ will not reflect the correct
    ///      depositted amounts. The master token is now held by the strategy.
    function totalAssets() public view virtual override returns (uint256) {
        if (address(strategy) == address(0)) {
            return 0;
        }

        return strategy.totalAssets();
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
        strategySet
    {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        _burn(_owner, _shares);

        // Strategy handles split and transfer to receiver
        uint256 tokenId = strategy.handleWithdraw(_receiver, _assets);

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);

        emit TokenIdWithdrawn(tokenId, _receiver);
    }

    /// @dev Transfer `assets` from caller to Vault, then to Strategy.
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
        strategySet
    {
        super._deposit(_caller, _receiver, _assets, _shares);

        // Approve strategy so it can transfer `_assets`.
        IERC20(asset()).approve(address(strategy), _assets);

        // Transfer assets to strategy
        // SafeERC20.safeTransfer(IERC20(asset()), address(strategy), _assets);

        // Strategy handles createLock and merge to masterTokenId
        strategy.handleDeposit(_assets);
    }

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev If `tokenId` position is already created on escrow,
    ///      this allows to still deposit which will mint the shares
    ///      depending on the amount that tokenId lock was created on escrow.
    function depositToken(uint256 _tokenId, address _receiver) public virtual strategySet returns (uint256) {
        uint256 assets = escrow.locked(_tokenId).amount;

        require(assets <= maxDeposit(_receiver), "ERC4626: deposit more than max");
        uint256 shares = previewDeposit(assets);

        // Transfer NFT directly to strategy (not vault)
        // Reverts if the caller does not own a veNFT.
        // If `amount` on tokenId is 0, either merge or withdrawal occurred in which case
        // `transferFrom` will anyways fail.
        lockNft.transferFrom(msg.sender, address(strategy), _tokenId);

        // Strategy handles merge to masterTokenId
        strategy.handleDepositToken(_tokenId);

        _mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, assets, shares);

        return shares;
    }

    /// @notice Allows to donate the assets only without minting shares.
    ///         This increases assets causing each share to cost more.
    /// @param _assets How much to donate.
    function donate(uint256 _assets) public virtual strategySet {
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), _assets);

        // Approve strategy so it can transfer `_assets`.
        IERC20(asset()).approve(address(strategy), _assets);

        // Strategy handles createLock and merge to masterTokenId
        strategy.handleDeposit(_assets);
    }

    /// @notice send veNFT mistakenly transferred to vault to `_receiver`.
    /// @dev If veNFT was deposited through `depositToken`, it would
    ///      be merged, hence such veNFTs can not be recovered.
    ///      This function only works for NFTs held by the vault, not the strategy.
    function recoverNFT(uint256 _tokenId, address _receiver) external auth(SWEEPER_ROLE) {
        lockNft.safeTransferFrom(address(this), _receiver, _tokenId);

        emit Sweep(_tokenId, _receiver);
    }

    /// @dev Allows an admin to set a new strategy contract.
    ///      Note: The strategy now holds the master token, not the vault.
    function _setStrategy(address _strategy) internal virtual {
        strategy = IStrategy(_strategy);

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
