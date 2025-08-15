// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IVKatMetadata, IVKat} from "./IVKatMetadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract VKatMetadata is IVKatMetadata, DaoAuthorizableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    mapping(uint256 => VKatMetaDataV1) private preferences;
    EnumerableSet.AddressSet internal rewardTokens;
    VKatMetaDataV1 private defaultPreferences;
    IVKat public vKat;

    function initialize(
        address _dao,
        address _vkat,
        address[] calldata _rewardTokens,
        VKatMetaDataV1 calldata _defaultPreferences
    ) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

        vKat = IVKat(_vkat);

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
    function setDefaultPreferences(
        VKatMetaDataV1 calldata _preferences
    ) external auth(ADMIN_ROLE) {
        _setDefaultPreferences(_preferences);
    }

    // ============ User Specific Functions =============

    /// @inheritdoc IVKatMetadata
    function setPreferences(
        uint256 _tokenId,
        VKatMetaDataV1 calldata _preferences
    ) public virtual {
        address ownerOf = vKat.ownerOf(_tokenId);

        if (msg.sender != ownerOf) {
            revert NotOwner();
        }

        _validatePreferences(_preferences);
        preferences[_tokenId] = _preferences;

        emit PreferencesSet(_tokenId, msg.sender, _preferences);
    }

    // =========== View Functions ==============

    /// @inheritdoc IVKatMetadata
    function isRewardToken(address _token) public view returns (bool) {
        return rewardTokens.contains(_token);
    }

    /// @inheritdoc IVKatMetadata
    /// @dev There could be a situation when `_tokenId` existed and user set
    ///      a preference for it. Later on, `_tokenId` was burnt. To still allow
    ///      the caller to know what the preferences was for that `_tokenId`,
    ///      we use low level call to fetch owner of the tokenId.
    function getPreferencesOrDefault(
        uint256 _tokenId
    ) external view returns (address, VKatMetaDataV1 memory) {
        VKatMetaDataV1 memory preferences_ = preferences[_tokenId];
        address owner = _getOwner(_tokenId);

        if (preferences_.votingPolicy == VotingPolicy.None) {
            preferences_ = getDefaultPreferences();
        }

        return (owner, preferences_);
    }

    /// @inheritdoc IVKatMetadata
    function getDefaultPreferences()
        public
        view
        virtual
        returns (VKatMetaDataV1 memory)
    {
        return defaultPreferences;
    }

    /// @inheritdoc IVKatMetadata
    function allowedRewardTokens() external view returns (address[] memory) {
        return rewardTokens.values();
    }

    /// @dev Helper function to validate the new default preferences and set it.
    function _setDefaultPreferences(
        VKatMetaDataV1 calldata _preferences
    ) internal virtual {
        _validatePreferences(_preferences);

        defaultPreferences = _preferences;
        emit DefaultPreferencesSet(_preferences);
    }

    /// @dev Helper function to fetch the token's owner. Most ERC721 reverts
    ///      if token doesn't have an owner, So we use low-level call to avoid revert.
    function _getOwner(uint256 _tokenId) private view returns (address) {
        (bool success, bytes memory data) = address(vKat).staticcall(
            abi.encodeCall(IVKat.ownerOf, (_tokenId))
        );
        if (success) {
            return abi.decode(data, (address));
        }
    }

    function _validatePreferences(
        VKatMetaDataV1 calldata _preferences
    ) internal virtual {
        // Validate that reward token is already added by admin in a whitelist.
        for (uint256 i = 0; i < _preferences.rewardTokens.length; i++) {
            address token = _preferences.rewardTokens[i];
            if (!isRewardToken(token)) {
                revert TokenNotWhitelisted(token);
            }
        }
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal override auth(ADMIN_ROLE) {}

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    uint256[43] private __gap;
}
