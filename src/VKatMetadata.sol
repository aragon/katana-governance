// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";

contract VKatMetadata is IVKatMetadata, DaoAuthorizable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The bytes32 identifier for admin role functions.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice The preferences per user.
    mapping(address => VKatMetaDataV1) private preferences;

    /// @notice The list of whitelisted tokens added by admin.
    EnumerableSet.AddressSet internal rewardTokens;

    /// @notice The default preferences that will be used if user hasn't set it.
    VKatMetaDataV1 private defaultPreferences;

    /// @notice The address of vkat token.
    address public vKat;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _dao,
        address _vkat,
        address[] calldata _rewardTokens,
        VKatMetaDataV1 calldata _defaultPreferences
    )
        external
        initializer
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

        vKat = _vkat;

        // whitelist reward tokens.
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address token = _rewardTokens[i];
            rewardTokens.add(token);
            emit RewardTokenAdded(token);
        }

        // Set the default preferences.
        _setDefaultPreferences(_defaultPreferences);
    }

    // ============= Admin Functions ====================

    /// @inheritdoc IVKatMetadata
    function addRewardToken(address _token) external auth(ADMIN_ROLE) {
        if (_token == address(0)) {
            revert ZeroAddress();
        }

        if (rewardTokens.contains(_token)) {
            revert TokenAlreadyInWhitelist(_token);
        }

        rewardTokens.add(_token);
        emit RewardTokenAdded(_token);
    }

    /// @inheritdoc IVKatMetadata
    function removeRewardToken(address _token) external auth(ADMIN_ROLE) {
        if (!rewardTokens.contains(_token)) {
            revert TokenNotInWhitelist(_token);
        }

        rewardTokens.remove(_token);
        emit RewardTokenRemoved(_token);
    }

    /// @inheritdoc IVKatMetadata
    function setDefaultPreferences(VKatMetaDataV1 calldata _preferences) external auth(ADMIN_ROLE) {
        _setDefaultPreferences(_preferences);
    }

    // ============ User Specific Functions =============

    /// @inheritdoc IVKatMetadata
    function setPreferences(VKatMetaDataV1 calldata _preferences) public virtual {
        _validatePreferences(_preferences);
        preferences[msg.sender] = _preferences;

        emit PreferencesSet(msg.sender, _preferences);
    }

    // =========== View Functions ==============

    /// @inheritdoc IVKatMetadata
    function isRewardToken(address _token) public view returns (bool) {
        return rewardTokens.contains(_token);
    }

    /// @inheritdoc IVKatMetadata
    function getPreferencesOrDefault(address _account) public view returns (VKatMetaDataV1 memory) {
        VKatMetaDataV1 memory preferences_ = preferences[_account];

        if (preferences_.rewardTokens.length == 0) {
            preferences_ = getDefaultPreferences();
        }

        return preferences_;
    }

    /// @inheritdoc IVKatMetadata
    function getDefaultPreferences() public view virtual returns (VKatMetaDataV1 memory) {
        return defaultPreferences;
    }

    /// @inheritdoc IVKatMetadata
    function allowedRewardTokens() external view returns (address[] memory) {
        return rewardTokens.values();
    }

    /// @dev Helper function to validate the new default preferences and set it.
    function _setDefaultPreferences(VKatMetaDataV1 calldata _preferences) internal virtual {
        _validatePreferences(_preferences);

        defaultPreferences = _preferences;
        emit DefaultPreferencesSet(_preferences);
    }

    function _validatePreferences(VKatMetaDataV1 calldata _preferences) internal virtual {
        if (_preferences.rewardTokens.length != _preferences.rewardTokenWeights.length) {
            revert LengthMismatch();
        }

        // Validate that reward token is already added by admin in a whitelist.
        for (uint256 i = 0; i < _preferences.rewardTokens.length; i++) {
            address token = _preferences.rewardTokens[i];
            if (!isRewardToken(token)) {
                revert TokenNotWhitelisted(token);
            }
        }
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal override auth(ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    uint256[45] private __gap;
}
