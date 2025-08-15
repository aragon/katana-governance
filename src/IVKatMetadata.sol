// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IVKat Interface
 * @dev Defines the necessary functions from the core vKAT NFT contract.
 */
interface IVKat {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedOrOwner(uint256 tokenId) external view returns (bool);
}

/**
 * @title IVKatMetadata Interface
 * @author Aragon
 * @notice Interface for the VKatMetadata sidecar contract that stores user preferences for vKAT NFTs
 * @dev This contract is designed to be UUPS-upgradable and decouples application-specific metadata from the core locking contract
 */
interface IVKatMetadata {
    // --- Data Structures ---

    /// @notice Defines the high-level voting strategy a user wishes to employ
    enum VotingPolicy {
        None,
        ProfitMaximize,
        Manual
        // ... other policies can be added (up to 256 supported)
    }

    /// @notice Stores the full set of preferences for a single vKAT NFT
    struct VKatMetaDataV1 {
        VotingPolicy votingPolicy;
        uint16[] rewardTokenWeights; // Relative weights, to be normalized by the consumer
        address[] rewardTokens;
    }

    // --- Events ---

    /// @notice Emitted when a user sets or updates their preferences
    event PreferencesSet(
        uint256 indexed tokenId,
        address indexed owner,
        VKatMetaDataV1 preferences
    );

    /// @notice Emitted when admin sets/updates the default preferences.
    event DefaultPreferencesSet(VKatMetaDataV1 preferences);

    /// @notice Emitted when a new reward token is added by the owner
    event RewardTokenAdded(address indexed token);

    /// @notice Emitted when a reward token is removed by the owner
    event RewardTokenRemoved(address indexed token);

    error NotOwner();
    error TokenNotWhitelisted(address token);
    error TokenAlreadyInWhitelist(address token);
    error TokenNotInWhitelist(address token);

    // --- Administrative Functions ---

    /**
     * @notice Adds a new token to the list of allowed reward tokens
     * @dev Can only be called by authorised caller
     * @param _rewardToken The address of the ERC20 token to add
     */
    function addRewardToken(address _rewardToken) external;

    /**
     * @notice Removes a token from the list of allowed reward tokens
     * @dev Can only be called by authorised caller. Off-chain consumers are responsible for ignoring user preferences for removed tokens
     * @param _rewardToken The address of the ERC20 token to remove
    */
    function removeRewardToken(address _rewardToken) external;

    /**
     * @notice Sets a default preference. This is what is returned for 
     * a tokenId that doesn't have custom preferences set.
     * @param _defaultPreferences The new default preferences.
    */
    function setDefaultPreferences(
        VKatMetaDataV1 calldata _defaultPreferences
    ) external;

    // --- User-Facing Functions ---

    /**
     * @notice Sets the preferences for a given vKAT NFT
     * @dev The caller must be the owner or approved caller of the _tokenId. Reward token weights are relative and do not need to sum to a specific value
     * @param _tokenId The ID of the vKAT NFT to update
     * @param _prefs The preference struct containing the desired settings
     */
    function setPreferences(
        uint256 _tokenId,
        VKatMetaDataV1 calldata _prefs
    ) external;

    // --- View Functions ---

    /**
     * @notice Retrieves the preferences for a given token, returning defaults if none are set
     * @dev Checks for token existence. If token no longer exists, reverts If custom preferences exist, returns them. Otherwise, returns the system default
     * @param _tokenId The ID of the vKAT NFT to query
     * @return The owner of `_tokenId` in question.
     * @return A VKatMetaDataV1 struct with the token's preferences
     */
    function getPreferencesOrDefault(
        uint256 _tokenId
    ) external view returns (address, VKatMetaDataV1 memory);

    /**
     * @notice Checks if a token is on the allowed reward tokens list
     * @param _token The address of the token to check
     * @return True if the token is allowed, false otherwise
     */
    function isRewardToken(address _token) external view returns (bool);

    /**
     * @notice Returns the address of the vKAT NFT contract
     * @return The address of the vKAT contract
     */
    function vKat() external view returns (IVKat);

    /**
     * @notice Returns the default preferences applied to vKAT NFTs without custom settings
     * @return The default VKatMetaDataV1 struct
     */
    function getDefaultPreferences()
        external
        view
        returns (VKatMetaDataV1 memory);

    /**
     * @notice Returns the list of all allowed reward tokens.
     */
    function allowedRewardTokens() external view returns (address[] memory);
}
