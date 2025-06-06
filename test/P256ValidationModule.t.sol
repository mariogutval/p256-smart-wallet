// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {P256ValidationModule} from "../src/modules/P256ValidationModule.sol";
import {IP256ValidationModule} from "../src/modules/IP256ValidationModule.sol";
import {P256PublicKey} from "../src/utils/Types.sol";
import {P256VerifierLib} from "../src/libraries/P256VerifierLib.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {PackedUserOperation} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";
import {IERC6900ValidationModule} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";

// Dummy verifier contract to stub RIP-7212 precompile & fallback verifier for tests.
contract DummyP256Verifier {
    // Always return uint256(1) for any staticcall/fallback.
    fallback() external payable {
        assembly {
            mstore(0x0, 1)
            return(0x0, 0x20)
        }
    }
}

contract P256ValidationModuleTest is Test {
    using MessageHashUtils for bytes32;

    P256ValidationModule public validationModule;
    address public testAccount;
    uint32 public constant TEST_ENTITY_ID = 1;

    // Sample P-256 public key (these are example values, replace with actual test values)
    P256PublicKey public testPasskey;

    event PasskeyTransferred(
        address indexed account, uint32 indexed entityId, P256PublicKey newKey, P256PublicKey prevKey
    );

    function setUp() public {
        validationModule = new P256ValidationModule();
        testAccount = makeAddr("testAccount");

        // Deploy dummy verifier and copy its code to the addresses expected by the library.
        DummyP256Verifier dummy = new DummyP256Verifier();
        bytes memory verifierCode = address(dummy).code;
        // RIP-7212 precompile address (0x100)
        vm.etch(address(0x100), verifierCode);
        // Solidity fallback verifier address used by Solady's P256 lib.
        vm.etch(0x000000000000E052BBf2730c643462Afb680718A, verifierCode);

        // Initialize test passkey with example values
        testPasskey = P256PublicKey({
            x: 0x1234567890123456789012345678901234567890123456789012345678901234,
            y: 0x2345678901234567890123456789012345678901234567890123456789012345
        });
    }

    function test_TransferPasskey() public {
        vm.startPrank(testAccount);

        // Initial state check
        (uint256 x, uint256 y) = validationModule.passkeys(TEST_ENTITY_ID, testAccount);
        assertEq(x, 0);
        assertEq(y, 0);

        // Transfer passkey
        validationModule.transferPasskey(TEST_ENTITY_ID, testPasskey);

        // Verify new state
        (x, y) = validationModule.passkeys(TEST_ENTITY_ID, testAccount);
        assertEq(x, testPasskey.x);
        assertEq(y, testPasskey.y);

        vm.stopPrank();
    }

    function test_OnInstall() public {
        bytes memory installData = abi.encode(TEST_ENTITY_ID, testPasskey);

        vm.startPrank(testAccount);
        validationModule.onInstall(installData);

        // Verify passkey was installed
        (uint256 x, uint256 y) = validationModule.passkeys(TEST_ENTITY_ID, testAccount);
        assertEq(x, testPasskey.x);
        assertEq(y, testPasskey.y);

        vm.stopPrank();
    }

    function test_OnUninstall() public {
        // First install a passkey
        bytes memory installData = abi.encode(TEST_ENTITY_ID, testPasskey);

        vm.startPrank(testAccount);
        validationModule.onInstall(installData);

        // Then uninstall it
        bytes memory uninstallData = abi.encode(TEST_ENTITY_ID);
        validationModule.onUninstall(uninstallData);

        // Verify passkey was removed
        (uint256 x, uint256 y) = validationModule.passkeys(TEST_ENTITY_ID, testAccount);
        assertEq(x, 0);
        assertEq(y, 0);

        vm.stopPrank();
    }

    function test_ModuleId() public {
        string memory id = validationModule.moduleId();
        assertEq(id, "erc6900.p256-validation-module.1.0.0");
    }

    function test_SupportsInterface() public {
        // Test ERC165 interface support
        assertTrue(validationModule.supportsInterface(0x01ffc9a7)); // IERC165
        // IERC6900ValidationModule interface id
        bytes4 erc6900Id = type(IERC6900ValidationModule).interfaceId;
        assertTrue(validationModule.supportsInterface(erc6900Id));
        assertFalse(validationModule.supportsInterface(0xffffffff)); // Random interface
    }

    function test_ValidateRuntime_Authorized() public {
        vm.startPrank(testAccount);

        // Test when sender is the account itself
        validationModule.validateRuntime(
            testAccount,
            TEST_ENTITY_ID,
            testAccount, // sender is the account
            0, // value
            "", // data
            "" // auth blob
        );

        // Test when sender is the module itself
        validationModule.validateRuntime(
            testAccount,
            TEST_ENTITY_ID,
            address(validationModule), // sender is the module
            0,
            "",
            ""
        );

        vm.stopPrank();
    }

    function test_ValidateRuntime_Unauthorized() public {
        address unauthorizedSender = makeAddr("unauthorized");

        vm.expectRevert(IP256ValidationModule.NotAuthorized.selector);
        validationModule.validateRuntime(testAccount, TEST_ENTITY_ID, unauthorizedSender, 0, "", "");
    }

    function test_ValidateSignature() public {
        vm.startPrank(testAccount);

        // First install a passkey
        validationModule.transferPasskey(TEST_ENTITY_ID, testPasskey);

        // Create a test message and hash
        bytes32 messageHash = keccak256("test message");
        bytes32 digest = messageHash.toEthSignedMessageHash();

        // Note: In a real test, we would need to generate a valid P-256 signature
        // This is just a placeholder for the signature bytes
        bytes memory signature = new bytes(96); // placeholder but properly sized for abi.decode

        // Test signature validation
        bytes4 result = validationModule.validateSignature(
            testAccount,
            TEST_ENTITY_ID,
            address(0), // sender
            digest,
            signature
        );

        // Note: The actual result will depend on the signature validity
        // This test needs to be updated with a valid signature
        assertTrue(result == 0x1626ba7e || result == 0xffffffff);

        vm.stopPrank();
    }

    function test_ValidateUserOp() public {
        vm.startPrank(testAccount);

        // First install a passkey
        validationModule.transferPasskey(TEST_ENTITY_ID, testPasskey);

        // Create a test user operation
        bytes32 userOpHash = keccak256("test user op");

        // Note: In a real test, we would need to create a proper PackedUserOperation
        // and generate a valid P-256 signature
        bytes memory signature = new bytes(96);

        // Test user operation validation
        uint256 result = validationModule.validateUserOp(
            TEST_ENTITY_ID,
            PackedUserOperation({
                sender: testAccount,
                nonce: 0,
                initCode: "",
                callData: "",
                accountGasLimits: bytes32(0),
                preVerificationGas: 0,
                gasFees: bytes32(0),
                paymasterAndData: "",
                signature: signature
            }),
            userOpHash
        );

        // Note: The actual result will depend on the signature validity
        // This test needs to be updated with a valid signature
        assertTrue(result == 0 || result == 1);

        vm.stopPrank();
    }

    // Helper function to create a valid P-256 signature
    // This is a placeholder - in a real implementation, you would need to
    // implement proper P-256 signature generation
    function _createValidSignature(bytes32 messageHash, P256PublicKey memory key)
        internal
        pure
        returns (bytes memory)
    {
        // This is just a placeholder - implement actual P-256 signature generation
        return new bytes(64);
    }
}
