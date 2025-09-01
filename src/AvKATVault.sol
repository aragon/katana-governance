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
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRewardsDistributor } from "./interfaces/IRewardsDistributor.sol";
import { AutoCompoundStrategy } from "./AutoCompoundStrategy.sol";

contract AvKATVault is ERC4626, Initializable, DaoAuthorizable {
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
        ERC4626(IERC20(_asset))
        ERC20("name", "symbol")
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
    {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        _burn(_owner, _shares);
        uint256 newTokenId = escrow.split(masterTokenId, _assets);
        lockNft.transferFrom(address(this), _receiver, newTokenId);

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
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

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Functions
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
