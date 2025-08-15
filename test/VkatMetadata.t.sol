// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/VKatMetadata.sol";
import "../src/IVKatMetadata.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { MockDAO } from "./mocks/MockDAO.sol";
import { MockVKatERC721 } from "./mocks/MockVKatERC721.sol";

contract VKatMetadataTest is Test {
    VKatMetadata public implementation;
    VKatMetadata public metadata;
    MockVKatERC721 public vkat;
    MockDAO public dao;

    address public admin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);

    address public token1 = address(0x100);
    address public token2 = address(0x101);
    address public token3 = address(0x102);
    address public nonWhitelistedToken = address(0x200);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IVKatMetadata.VKatMetaDataV1 defaultPrefs;

    event PreferencesSet(uint256 indexed tokenId, address indexed owner, IVKatMetadata.VKatMetaDataV1 preferences);

    event DefaultPreferencesSet(IVKatMetadata.VKatMetaDataV1 preferences);
    event RewardTokenAdded(address indexed token);
    event RewardTokenRemoved(address indexed token);

    function setUp() public {
        // Deploy mock contracts
        vkat = new MockVKatERC721();
        dao = new MockDAO();

        // Setup default preferences
        defaultPrefs.votingPolicy = IVKatMetadata.VotingPolicy.ProfitMaximize;
        defaultPrefs.rewardTokens = new address[](2);
        defaultPrefs.rewardTokens[0] = token1;
        defaultPrefs.rewardTokens[1] = token2;
        defaultPrefs.rewardTokenWeights = new uint16[](2);
        defaultPrefs.rewardTokenWeights[0] = 60;
        defaultPrefs.rewardTokenWeights[1] = 40;

        // Deploy implementation
        implementation = new VKatMetadata();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            VKatMetadata.initialize.selector, address(dao), address(vkat), defaultPrefs.rewardTokens, defaultPrefs
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        metadata = VKatMetadata(address(proxy));

        // Setup DAO permissions
        // metadata.initialize(address(dao));
        dao.grant(address(metadata), admin, ADMIN_ROLE);

        // Label addresses for better test output
        vm.label(admin, "Admin");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(address(vkat), "VKat NFT");
        vm.label(address(metadata), "Metadata");
        vm.label(address(dao), "DAO");
    }

    modifier prankAdmin() {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    // ============= Initialization Tests =============

    function test__Initialization() public {
        assertEq(address(metadata.vKat()), address(vkat));

        // Check default preferences
        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getDefaultPreferences();
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.ProfitMaximize));
        assertEq(prefs.rewardTokens.length, 2);
        assertEq(prefs.rewardTokens[0], token1);
        assertEq(prefs.rewardTokens[1], token2);
        assertEq(prefs.rewardTokenWeights[0], 60);
        assertEq(prefs.rewardTokenWeights[1], 40);

        // Check whitelisted tokens
        assertTrue(metadata.isRewardToken(token1));
        assertTrue(metadata.isRewardToken(token2));
        assertFalse(metadata.isRewardToken(token3));
    }

    function test_Revert_IfInitializeAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        metadata.initialize(address(dao), address(vkat), new address[](0), defaultPrefs);
    }

    // ============= Admin Functions Tests =============

    function test_AddRewardToken() public prankAdmin {
        assertFalse(metadata.isRewardToken(token3));

        vm.expectEmit(true, false, false, false);
        emit RewardTokenAdded(token3);
        metadata.addRewardToken(token3);

        assertTrue(metadata.isRewardToken(token3));
    }

    function test_AddRewardTokenAlreadyExists() public prankAdmin {
        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenAlreadyInWhitelist.selector, token1));
        metadata.addRewardToken(token1);
    }

    function test_AddRewardTokenUnauthorized() public {
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.addRewardToken(token3);

        vm.stopPrank();
    }

    function test_RemoveRewardToken() public prankAdmin {
        assertTrue(metadata.isRewardToken(token1));

        vm.expectEmit(true, false, false, false);
        emit RewardTokenRemoved(token1);
        metadata.removeRewardToken(token1);

        assertFalse(metadata.isRewardToken(token1));
    }

    function test_RemoveRewardTokenNotInWhitelist() public prankAdmin {
        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenNotInWhitelist.selector, token3));
        metadata.removeRewardToken(token3);
    }

    function test_RemoveRewardTokenUnauthorized() public {
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.removeRewardToken(token1);

        vm.stopPrank();
    }

    function test_SetDefaultPreferences() public prankAdmin {
        IVKatMetadata.VKatMetaDataV1 memory newDefaults;
        newDefaults.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        newDefaults.rewardTokens = new address[](1);
        newDefaults.rewardTokens[0] = token2;
        newDefaults.rewardTokenWeights = new uint16[](1);
        newDefaults.rewardTokenWeights[0] = 100;

        vm.expectEmit(false, false, false, true);
        emit DefaultPreferencesSet(newDefaults);
        metadata.setDefaultPreferences(newDefaults);

        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getDefaultPreferences();
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.Manual));
        assertEq(prefs.rewardTokens.length, 1);
        assertEq(prefs.rewardTokens[0], token2);
        assertEq(prefs.rewardTokenWeights[0], 100);
    }

    function test_SetDefaultPreferencesWithNonWhitelistedToken() public prankAdmin {
        IVKatMetadata.VKatMetaDataV1 memory newDefaults;
        newDefaults.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        newDefaults.rewardTokens = new address[](1);
        newDefaults.rewardTokens[0] = nonWhitelistedToken;
        newDefaults.rewardTokenWeights = new uint16[](1);
        newDefaults.rewardTokenWeights[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenNotWhitelisted.selector, nonWhitelistedToken));
        metadata.setDefaultPreferences(newDefaults);
    }

    function test_SetDefaultPreferencesUnauthorized() public {
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.setDefaultPreferences(defaultPrefs);

        vm.stopPrank();
    }

    // ============= User Functions Tests =============

    function test_SetPreferences() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        vm.startPrank(alice);

        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        customPrefs.rewardTokens = new address[](2);
        customPrefs.rewardTokens[0] = token2;
        customPrefs.rewardTokens[1] = token1;
        customPrefs.rewardTokenWeights = new uint16[](2);
        customPrefs.rewardTokenWeights[0] = 30;
        customPrefs.rewardTokenWeights[1] = 70;

        vm.expectEmit(true, true, false, true);
        emit PreferencesSet(tokenId, alice, customPrefs);
        metadata.setPreferences(tokenId, customPrefs);

        (address owner, IVKatMetadata.VKatMetaDataV1 memory prefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, alice);
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.Manual));
        assertEq(prefs.rewardTokens.length, 2);
        assertEq(prefs.rewardTokens[0], token2);
        assertEq(prefs.rewardTokens[1], token1);
        assertEq(prefs.rewardTokenWeights[0], 30);
        assertEq(prefs.rewardTokenWeights[1], 70);

        vm.stopPrank();
    }

    function test_SetPreferencesNotOwner() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        vm.startPrank(bob);

        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;

        vm.expectRevert(IVKatMetadata.NotOwner.selector);
        metadata.setPreferences(tokenId, customPrefs);

        vm.stopPrank();
    }

    function test_SetPreferencesWithNonWhitelistedToken() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        vm.startPrank(alice);

        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        customPrefs.rewardTokens = new address[](1);
        customPrefs.rewardTokens[0] = nonWhitelistedToken;
        customPrefs.rewardTokenWeights = new uint16[](1);
        customPrefs.rewardTokenWeights[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenNotWhitelisted.selector, nonWhitelistedToken));
        metadata.setPreferences(tokenId, customPrefs);

        vm.stopPrank();
    }

    function test_SetPreferencesNonExistentToken() public {
        uint256 nonExistentTokenId = 999;

        vm.startPrank(alice);

        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;

        // This should revert with ERC721 error since token doesn't exist
        vm.expectRevert("ERC721: invalid token ID");
        metadata.setPreferences(nonExistentTokenId, customPrefs);

        vm.stopPrank();
    }

    // ============= View Functions Tests =============

    function test_GetPreferencesOrDefaultWithCustomPreferences() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        // Set custom preferences
        vm.startPrank(alice);
        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        customPrefs.rewardTokens = new address[](1);
        customPrefs.rewardTokens[0] = token1;
        customPrefs.rewardTokenWeights = new uint16[](1);
        customPrefs.rewardTokenWeights[0] = 100;

        metadata.setPreferences(tokenId, customPrefs);
        vm.stopPrank();

        (address owner, IVKatMetadata.VKatMetaDataV1 memory prefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, alice);
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.Manual));
        assertEq(prefs.rewardTokens.length, 1);
        assertEq(prefs.rewardTokens[0], token1);
    }

    function test_GetPreferencesOrDefaultWithoutCustomPreferences() public {
        // Mint NFT to alice but don't set preferences
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        (address owner, IVKatMetadata.VKatMetaDataV1 memory prefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, alice);
        // Should return default preferences
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.ProfitMaximize));
        assertEq(prefs.rewardTokens.length, 2);
        assertEq(prefs.rewardTokens[0], token1);
        assertEq(prefs.rewardTokens[1], token2);
    }

    function test_GetPreferencesOrDefaultForBurnedToken() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        // Set custom preferences
        vm.startPrank(alice);
        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        customPrefs.rewardTokens = new address[](1);
        customPrefs.rewardTokens[0] = token1;
        customPrefs.rewardTokenWeights = new uint16[](1);
        customPrefs.rewardTokenWeights[0] = 100;

        metadata.setPreferences(tokenId, customPrefs);
        vm.stopPrank();

        // Burn the token
        vm.prank(address(this));
        vkat.burn(tokenId);

        // Should still return preferences but owner should be address(0)
        (address owner, IVKatMetadata.VKatMetaDataV1 memory prefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, address(0));
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.Manual));
        assertEq(prefs.rewardTokens.length, 1);
    }

    function test_AllowedRewardTokens() public {
        address[] memory tokens = metadata.allowedRewardTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);

        // Add a new token
        vm.prank(admin);
        metadata.addRewardToken(token3);

        tokens = metadata.allowedRewardTokens();
        assertEq(tokens.length, 3);

        // Remove a token
        vm.prank(admin);
        metadata.removeRewardToken(token1);

        tokens = metadata.allowedRewardTokens();
        assertEq(tokens.length, 2);
        // Note: EnumerableSet doesn't guarantee order after removal
        assertTrue(tokens[0] == token3 || tokens[0] == token2);
        assertTrue(tokens[1] == token3 || tokens[1] == token2);
    }

    // ============= Edge Cases & Complex Scenarios =============

    function test_MultiplePreferenceUpdates() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        vm.startPrank(alice);

        // First update
        IVKatMetadata.VKatMetaDataV1 memory prefs1;
        prefs1.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        metadata.setPreferences(tokenId, prefs1);

        // Second update
        IVKatMetadata.VKatMetaDataV1 memory prefs2;
        prefs2.votingPolicy = IVKatMetadata.VotingPolicy.ProfitMaximize;
        prefs2.rewardTokens = new address[](1);
        prefs2.rewardTokens[0] = token2;
        prefs2.rewardTokenWeights = new uint16[](1);
        prefs2.rewardTokenWeights[0] = 100;
        metadata.setPreferences(tokenId, prefs2);

        vm.stopPrank();

        (address owner, IVKatMetadata.VKatMetaDataV1 memory finalPrefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, alice);
        assertEq(uint8(finalPrefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.ProfitMaximize));
        assertEq(finalPrefs.rewardTokens.length, 1);
        assertEq(finalPrefs.rewardTokens[0], token2);
    }

    function test_EmptyRewardTokensAndWeights() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        vm.startPrank(alice);

        IVKatMetadata.VKatMetaDataV1 memory prefs;
        prefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        prefs.rewardTokens = new address[](0);
        prefs.rewardTokenWeights = new uint16[](0);

        metadata.setPreferences(tokenId, prefs);

        vm.stopPrank();

        (address owner, IVKatMetadata.VKatMetaDataV1 memory storedPrefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, alice);
        assertEq(storedPrefs.rewardTokens.length, 0);
        assertEq(storedPrefs.rewardTokenWeights.length, 0);
    }

    function test_TransferAndPreferences() public {
        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        // Alice sets preferences
        vm.startPrank(alice);
        IVKatMetadata.VKatMetaDataV1 memory alicePrefs;
        alicePrefs.votingPolicy = IVKatMetadata.VotingPolicy.Manual;
        metadata.setPreferences(tokenId, alicePrefs);

        // Alice transfers to Bob
        vkat.transferFrom(alice, bob, tokenId);
        vm.stopPrank();

        // Bob should now be able to update preferences
        vm.startPrank(bob);
        IVKatMetadata.VKatMetaDataV1 memory bobPrefs;
        bobPrefs.votingPolicy = IVKatMetadata.VotingPolicy.ProfitMaximize;
        metadata.setPreferences(tokenId, bobPrefs);
        vm.stopPrank();

        (address owner, IVKatMetadata.VKatMetaDataV1 memory prefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(owner, bob);
        assertEq(uint8(prefs.votingPolicy), uint8(IVKatMetadata.VotingPolicy.ProfitMaximize));

        // Alice should no longer be able to update
        vm.startPrank(alice);
        vm.expectRevert(IVKatMetadata.NotOwner.selector);
        metadata.setPreferences(tokenId, alicePrefs);
        vm.stopPrank();
    }

    // ============= Upgrade Tests =============

    function test_UpgradeAuthorized() public prankAdmin {
        // Deploy new implementation
        VKatMetadata newImplementation = new VKatMetadata();

        // Upgrade should succeed
        metadata.upgradeTo(address(newImplementation));

        assertEq(metadata.implementation(), address(newImplementation));
    }

    function test_UpgradeUnauthorized() public {
        vm.startPrank(alice);

        VKatMetadata newImplementation = new VKatMetadata();

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.upgradeTo(address(newImplementation));

        vm.stopPrank();
    }

    // ============= Fuzz Tests =============

    function test_FuzzSetPreferences(uint8 _votingPolicy, uint256 _numTokens, uint256 _seed) public {
        vm.assume(_votingPolicy > 0 && _votingPolicy <= uint8(type(IVKatMetadata.VotingPolicy).max)); // Valid voting
            // policies
        vm.assume(_numTokens <= 10); // Reasonable number of tokens

        // Mint NFT to alice
        vm.prank(address(this));
        uint256 tokenId = vkat.mint(alice);

        // Add required tokens to whitelist
        vm.startPrank(admin);
        address[] memory fuzzTokens = new address[](_numTokens);
        for (uint256 i = 0; i < _numTokens; i++) {
            fuzzTokens[i] = address(uint160(0x1000 + i));
            if (!metadata.isRewardToken(fuzzTokens[i])) {
                metadata.addRewardToken(fuzzTokens[i]);
            }
        }
        vm.stopPrank();

        // Create preferences with fuzzed data
        vm.startPrank(alice);
        IVKatMetadata.VKatMetaDataV1 memory prefs;
        prefs.votingPolicy = IVKatMetadata.VotingPolicy(_votingPolicy);
        prefs.rewardTokens = fuzzTokens;
        prefs.rewardTokenWeights = new uint16[](_numTokens);

        for (uint256 i = 0; i < _numTokens; i++) {
            prefs.rewardTokenWeights[i] = uint16(uint256(keccak256(abi.encode(_seed, i))) % 10000);
        }

        metadata.setPreferences(tokenId, prefs);
        vm.stopPrank();

        // // Verify preferences were set correctly
        (, IVKatMetadata.VKatMetaDataV1 memory storedPrefs) = metadata.getPreferencesOrDefault(tokenId);

        assertEq(uint8(storedPrefs.votingPolicy), _votingPolicy);
        assertEq(storedPrefs.rewardTokens.length, _numTokens);
        assertEq(storedPrefs.rewardTokenWeights.length, _numTokens);
    }

    function test_FuzzAddRemoveTokens(uint256 _numOperations, uint256 _seed) public {
        vm.assume(_numOperations <= 20);

        vm.startPrank(admin);

        for (uint256 i = 0; i < _numOperations; i++) {
            address token = address(uint160(0x2000 + i));
            bool shouldAdd = uint256(keccak256(abi.encode(_seed, i))) % 2 == 0;

            if (shouldAdd) {
                if (!metadata.isRewardToken(token)) {
                    metadata.addRewardToken(token);
                    assertTrue(metadata.isRewardToken(token));
                }
            } else {
                if (metadata.isRewardToken(token)) {
                    metadata.removeRewardToken(token);
                    assertFalse(metadata.isRewardToken(token));
                }
            }
        }

        vm.stopPrank();
    }
}
