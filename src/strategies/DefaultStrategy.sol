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

import { NFTBaseStrategy } from "../abstracts/NFTBaseStrategy.sol";

contract DefaultStrategy is Initializable, UUPSUpgradeable, DaoAuthorizable, NFTBaseStrategy {
    using SafeERC20 for IERC20;

    ///@notice The bytes32 identifier for admin role functions.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    function initialize(address _dao, address _escrow, address _allowed) external reinitializer(1) {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __NFTBaseStrategy_init(_escrow, VotingEscrow(_escrow).token(), VotingEscrow(_escrow).lockNFT(), _allowed);
    }

    function initializeAllowed(address _vault) external reinitializer(2) {
        allowed = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                        Upgrade
    //////////////////////////////////////////////////////////////*/
    function _authorizeUpgrade(address) internal virtual override auth(ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[41] private __gap;
}
