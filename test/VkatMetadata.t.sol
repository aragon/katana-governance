// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/VKatMetadata.sol";
import "../src/interfaces/IVKatMetadata.sol";
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

    function setUp() public {
        // Deploy mock contracts
        vkat = new MockVKatERC721();
        dao = new MockDAO();

        // Setup default preferences
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

        metadata = VKatMetadata(address(new ERC1967Proxy(address(implementation), initData)));

        // Setup DAO permissions
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

    function test_Initialization() public view {
        assertEq(address(metadata.vKat()), address(vkat));

        // Check default preferences
        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getDefaultPreferences();
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
        emit IVKatMetadata.RewardTokenAdded(token3);
        metadata.addRewardToken(token3);

        assertTrue(metadata.isRewardToken(token3));
    }

    function testRevert_IfRewardTokenAlreadyExists() public prankAdmin {
        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenAlreadyInWhitelist.selector, token1));
        metadata.addRewardToken(token1);
    }

    function testRevert_IfZeroAddress() public prankAdmin {
        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.ZeroAddress.selector));
        metadata.addRewardToken(address(0));
    }

    function testRevert_AddRewardTokenIfUnauthorized() public {
        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.addRewardToken(token3);
    }

    function test_RemoveRewardToken() public prankAdmin {
        assertTrue(metadata.isRewardToken(token1));

        vm.expectEmit(true, false, false, false);
        emit IVKatMetadata.RewardTokenRemoved(token1);
        metadata.removeRewardToken(token1);

        assertFalse(metadata.isRewardToken(token1));
    }

    function testRevert_RemoveRewardTokenNotInWhitelist() public prankAdmin {
        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenNotInWhitelist.selector, token3));
        metadata.removeRewardToken(token3);
    }

    function testRevert_RemoveRewardTokenIfUnauthorized() public {
        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.removeRewardToken(token1);
    }

    function testRevert_SetDefaultPreferencesWithNonWhitelistedToken() public prankAdmin {
        IVKatMetadata.VKatMetaDataV1 memory newDefaults;
        newDefaults.rewardTokens = new address[](1);
        newDefaults.rewardTokens[0] = nonWhitelistedToken;
        newDefaults.rewardTokenWeights = new uint16[](1);
        newDefaults.rewardTokenWeights[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenNotWhitelisted.selector, nonWhitelistedToken));
        metadata.setDefaultPreferences(newDefaults);
    }

    function testRevert_SetDefaultPreferencesIfUnauthorized() public {
        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        metadata.setDefaultPreferences(defaultPrefs);
    }

    function testRevert_IfTokenLengthMismatchWithWeights() public prankAdmin {
        IVKatMetadata.VKatMetaDataV1 memory newDefaults;
        newDefaults.rewardTokens = new address[](1);
        newDefaults.rewardTokens[0] = nonWhitelistedToken;
        newDefaults.rewardTokenWeights = new uint16[](2);
        newDefaults.rewardTokenWeights[0] = 100;
        newDefaults.rewardTokenWeights[1] = 100;

        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.LengthMismatch.selector));
        metadata.setDefaultPreferences(newDefaults);
    }

    function test_SetDefaultPreferences() public prankAdmin {
        IVKatMetadata.VKatMetaDataV1 memory newDefaults;
        newDefaults.rewardTokens = new address[](1);
        newDefaults.rewardTokens[0] = token2;
        newDefaults.rewardTokenWeights = new uint16[](1);
        newDefaults.rewardTokenWeights[0] = 100;

        vm.expectEmit(false, false, false, true);
        emit IVKatMetadata.DefaultPreferencesSet(newDefaults);
        metadata.setDefaultPreferences(newDefaults);

        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getDefaultPreferences();
        assertEq(prefs.rewardTokens.length, 1);
        assertEq(prefs.rewardTokens[0], token2);
        assertEq(prefs.rewardTokenWeights[0], 100);
    }

    // ============= User Functions Tests =============

    function testRevert_SetPreferencesWithNonWhitelistedToken() public {
        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.rewardTokens = new address[](1);
        customPrefs.rewardTokens[0] = nonWhitelistedToken;
        customPrefs.rewardTokenWeights = new uint16[](1);
        customPrefs.rewardTokenWeights[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.TokenNotWhitelisted.selector, nonWhitelistedToken));
        vm.prank(alice);
        metadata.setPreferences(customPrefs);
    }

    function testRevert_SetPreferencesWhenLengthMismatch() public {
        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.rewardTokens = new address[](1);
        customPrefs.rewardTokens[0] = nonWhitelistedToken;
        customPrefs.rewardTokenWeights = new uint16[](2);
        customPrefs.rewardTokenWeights[0] = 100;
        customPrefs.rewardTokenWeights[1] = 100;

        vm.expectRevert(abi.encodeWithSelector(IVKatMetadata.LengthMismatch.selector));
        vm.prank(alice);
        metadata.setPreferences(customPrefs);
    }

    function test_SetPreferences() public {
        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.rewardTokens = new address[](2);
        customPrefs.rewardTokens[0] = token2;
        customPrefs.rewardTokens[1] = token1;
        customPrefs.rewardTokenWeights = new uint16[](2);
        customPrefs.rewardTokenWeights[0] = 30;
        customPrefs.rewardTokenWeights[1] = 70;

        vm.expectEmit(true, true, false, true);
        vm.prank(alice);
        emit IVKatMetadata.PreferencesSet(alice, customPrefs);
        metadata.setPreferences(customPrefs);

        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getPreferencesOrDefault(alice);

        assertEq(prefs.rewardTokens.length, 2);
        assertEq(prefs.rewardTokens[0], token2);
        assertEq(prefs.rewardTokens[1], token1);
        assertEq(prefs.rewardTokenWeights[0], 30);
        assertEq(prefs.rewardTokenWeights[1], 70);
    }

    // ============= View Functions Tests =============

    function test_GetPreferencesOrDefaultWithCustomPreferences() public {
        // Set custom preferences
        IVKatMetadata.VKatMetaDataV1 memory customPrefs;
        customPrefs.rewardTokens = new address[](1);
        customPrefs.rewardTokens[0] = token1;
        customPrefs.rewardTokenWeights = new uint16[](1);
        customPrefs.rewardTokenWeights[0] = 100;

        vm.prank(alice);
        metadata.setPreferences(customPrefs);

        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getPreferencesOrDefault(alice);

        assertEq(prefs.rewardTokens.length, 1);
        assertEq(prefs.rewardTokens[0], token1);
    }

    function test_GetPreferencesOrDefaultWithoutCustomPreferences() public view {
        IVKatMetadata.VKatMetaDataV1 memory prefs = metadata.getPreferencesOrDefault(alice);

        // Should return default preferences
        assertEq(prefs.rewardTokens.length, 2);
        assertEq(prefs.rewardTokens[0], token1);
        assertEq(prefs.rewardTokens[1], token2);
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
        // First update
        IVKatMetadata.VKatMetaDataV1 memory prefs1;
        vm.prank(alice);
        metadata.setPreferences(prefs1);

        // Second update
        IVKatMetadata.VKatMetaDataV1 memory prefs2;
        prefs2.rewardTokens = new address[](1);
        prefs2.rewardTokens[0] = token2;
        prefs2.rewardTokenWeights = new uint16[](1);
        prefs2.rewardTokenWeights[0] = 100;

        vm.prank(alice);
        metadata.setPreferences(prefs2);

        IVKatMetadata.VKatMetaDataV1 memory finalPrefs = metadata.getPreferencesOrDefault(alice);

        assertEq(finalPrefs.rewardTokens.length, 1);
        assertEq(finalPrefs.rewardTokens[0], token2);
    }

    function test_EmptyRewardTokensAndWeights() public {
        IVKatMetadata.VKatMetaDataV1 memory prefs;
        prefs.rewardTokens = new address[](1);
        prefs.rewardTokens[0] = token2;
        prefs.rewardTokenWeights = new uint16[](1);
        prefs.rewardTokenWeights[0] = 100;
        vm.prank(alice);
        metadata.setPreferences(prefs);

        IVKatMetadata.VKatMetaDataV1 memory prefs2;
        prefs2.rewardTokens = new address[](0);
        prefs2.rewardTokenWeights = new uint16[](0);

        vm.prank(alice);
        metadata.setPreferences(prefs2);

        // Still must get default preferences as alice set it back to empty.
        IVKatMetadata.VKatMetaDataV1 memory storedPrefs = metadata.getPreferencesOrDefault(alice);

        assertEq(storedPrefs.rewardTokens.length, 2);
        assertEq(storedPrefs.rewardTokenWeights.length, 2);
    }

    // ============= Upgrade Tests =============

    function testRevert_UpgradeAuthorized() public prankAdmin {
        // Deploy new implementation
        VKatMetadata newImplementation = new VKatMetadata();

        // Upgrade should succeed
        metadata.upgradeTo(address(newImplementation));

        assertEq(metadata.implementation(), address(newImplementation));
    }

    function testRevert_UpgradeUnauthorized() public {
        address newImplementation = address(new VKatMetadata());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(metadata), address(alice), ADMIN_ROLE
            )
        );
        vm.prank(alice);
        metadata.upgradeTo(newImplementation);
    }

    // ============= Fuzz Tests =============

    function test_FuzzSetPreferences(uint256 _numTokens, uint256 _seed) public {
        vm.assume(_numTokens > 0 && _numTokens <= 10); // Reasonable number of tokens

        // Add required tokens to whitelist
        vm.startPrank(admin);
        address[] memory fuzzTokens = new address[](_numTokens);
        for (uint256 i = 0; i < _numTokens; i++) {
            fuzzTokens[i] = address(uint160(0x1000 + i));
            metadata.addRewardToken(fuzzTokens[i]);
        }
        vm.stopPrank();

        // Create preferences with fuzzed data
        IVKatMetadata.VKatMetaDataV1 memory prefs;
        prefs.rewardTokens = fuzzTokens;
        prefs.rewardTokenWeights = new uint16[](_numTokens);

        for (uint256 i = 0; i < _numTokens; i++) {
            prefs.rewardTokenWeights[i] = uint16(uint256(keccak256(abi.encode(_seed, i))) % 10000);
        }

        vm.prank(alice);
        metadata.setPreferences(prefs);

        // Verify preferences were set correctly
        IVKatMetadata.VKatMetaDataV1 memory storedPrefs = metadata.getPreferencesOrDefault(alice);

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
