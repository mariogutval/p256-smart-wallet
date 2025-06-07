// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin imports
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ERC6900 imports
import {PackedUserOperation} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";
import {IERC6900ValidationModule} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";

// FCL imports
import {FCL_ecdsa_utils} from "@FCL/FCL_ecdsa_utils.sol";

// Local imports
import {BaseTest} from "../helpers/BaseTest.sol";
import {P256ValidationModule} from "../../src/modules/P256ValidationModule.sol";
import {IP256ValidationModule} from "../../src/modules/IP256ValidationModule.sol";
import {P256PublicKey} from "../../src/utils/Types.sol";
import {P256VerifierLib} from "../../src/libraries/P256VerifierLib.sol";
import {SigningUtilsLib} from "../helpers/SigningUtilsLib.sol";

contract P256ValidationModuleTest is BaseTest {
    using MessageHashUtils for bytes32;

    P256ValidationModule public validationModule;
    TestUser public testUser;
    P256PublicKey public testPasskey;

    event PasskeyTransferred(
        address indexed account, uint32 indexed entityId, P256PublicKey newKey, P256PublicKey prevKey
    );

    function setUp() public {
        validationModule = new P256ValidationModule();
        testUser = createUser("testUser");
        testPasskey = createP256Key(testUser.privateKey);
    }

    function test_TransferPasskey() public {
        vm.startPrank(testUser.addr);

        // Initial state check
        (uint256 x, uint256 y) = validationModule.passkeys(DEFAULT_ENTITY_ID, testUser.addr);
        assertEq(x, 0);
        assertEq(y, 0);

        // Transfer passkey
        validationModule.transferPasskey(DEFAULT_ENTITY_ID, testPasskey);

        // Verify new state
        (x, y) = validationModule.passkeys(DEFAULT_ENTITY_ID, testUser.addr);
        assertEq(x, testPasskey.x);
        assertEq(y, testPasskey.y);

        vm.stopPrank();
    }

    function test_OnInstall() public {
        bytes memory installData = abi.encode(DEFAULT_ENTITY_ID, testPasskey);

        vm.startPrank(testUser.addr);
        validationModule.onInstall(installData);

        // Verify passkey was installed
        (uint256 x, uint256 y) = validationModule.passkeys(DEFAULT_ENTITY_ID, testUser.addr);
        assertEq(x, testPasskey.x);
        assertEq(y, testPasskey.y);

        vm.stopPrank();
    }

    function test_OnUninstall() public {
        // First install a passkey
        bytes memory installData = abi.encode(DEFAULT_ENTITY_ID, testPasskey);

        vm.startPrank(testUser.addr);
        validationModule.onInstall(installData);

        // Then uninstall it
        bytes memory uninstallData = abi.encode(DEFAULT_ENTITY_ID);
        validationModule.onUninstall(uninstallData);

        // Verify passkey was removed
        (uint256 x, uint256 y) = validationModule.passkeys(DEFAULT_ENTITY_ID, testUser.addr);
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
        vm.startPrank(testUser.addr);

        // Test when sender is the account itself
        validationModule.validateRuntime(
            testUser.addr,
            DEFAULT_ENTITY_ID,
            testUser.addr, // sender is the account
            0, // value
            "", // data
            "" // auth blob
        );

        // Test when sender is the module itself
        validationModule.validateRuntime(
            testUser.addr,
            DEFAULT_ENTITY_ID,
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
        validationModule.validateRuntime(testUser.addr, DEFAULT_ENTITY_ID, unauthorizedSender, 0, "", "");
    }

    function test_ValidateSignature() public {
        // First register the passkey
        vm.startPrank(testUser.addr);
        validationModule.transferPasskey(DEFAULT_ENTITY_ID, testPasskey);
        vm.stopPrank();

        // Create a test message hash
        bytes32 messageHash = keccak256("test message");

        // Create a valid signature
        bytes memory signature = SigningUtilsLib.signHashP256(testUser.privateKey, messageHash);

        // Create a replay-safe hash
        bytes32 replaySafeHash = validationModule.replaySafeHash(testUser.addr, messageHash);

        // Validate the signature
        bytes4 result = validationModule.validateSignature(
            testUser.addr,
            DEFAULT_ENTITY_ID,
            address(0), // sender
            messageHash,
            signature
        );

        assertTrue(result == _1271_MAGIC_VALUE, "Signature validation failed");
    }

    function test_ValidateUserOp() public {
        vm.startPrank(testUser.addr);

        // First install a passkey
        validationModule.transferPasskey(DEFAULT_ENTITY_ID, testPasskey);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: testUser.addr,
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: ""
        });

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        bytes memory signature = SigningUtilsLib.signHashP256(testUser.privateKey, userOpHash);
        userOp.signature = signature;

        uint256 result = validationModule.validateUserOp(DEFAULT_ENTITY_ID, userOp, userOpHash);

        assertTrue(result == 0);

        vm.stopPrank();
    }
}
