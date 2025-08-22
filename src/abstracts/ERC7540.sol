// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import { VotingEscrow, EscrowIVotesAdapter, GaugeVoter, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizable } from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC7540 } from "../interfaces/IERC7540.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ERC7540 is IERC7540, ERC4626 {
    uint256 internal constant REQUEST_ID = 0;
    uint256 internal constant MAX_REQUESTS = 3;

    mapping(address => RedemptionRequest[]) internal _pendingRedemption;

    uint256 internal _totalPendingRedeemAssets;
    mapping(address => mapping(address => bool)) public isOperator;

    struct RedemptionRequest {
        uint256 assets;
        uint256 shares;
        uint256 tokenId;
        uint32 claimableTimestamp;
    }

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol
    )
        ERC4626(IERC20(_asset))
        ERC20(_name, _symbol)
    { }

    modifier controllerAllowed(address _controller) {
        if (_controller != msg.sender && !isOperator[_controller][msg.sender]) {
            revert InvalidCaller();
        }

        _;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    function setOperator(address _operator, bool _approved) public virtual returns (bool success) {
        if (msg.sender == _operator) {
            revert CannotSetCallerAsOperator();
        }

        isOperator[msg.sender][_operator] = _approved;
        emit OperatorSet(msg.sender, _operator, _approved);
        success = true;
    }
}
