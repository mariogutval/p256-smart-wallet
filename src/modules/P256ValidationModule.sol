// SPDX-License-Identifier: MIT
pragma solidity =0.8.30;

/* ─── ERC-6900 interfaces ──────────────────────────────────────────────── */
import {
    IERC6900ValidationModule,
    PackedUserOperation
} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IP256ValidationModule} from "./IP256ValidationModule.sol";
import {P256PublicKey} from "../utils/Types.sol";

import {ReplaySafeWrapper} from "@erc6900/reference-implementation/modules/ReplaySafeWrapper.sol";
import {BaseModule} from "@erc6900/reference-implementation/modules/BaseModule.sol";

/* ─── Signature helpers – same lib you already used in your PoC ─────────── */
import {P256VerifierLib} from "../libraries/P256VerifierLib.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/* ───────────────────────────── Contract ──────────────────────────────── */
/// @title P-256 (WebAuthn) Validation Module
/// @author ERC-6900 community
/// @notice Validation module that stores one P-256 pass-key per (account, entityId)
///         and validates signatures & runtime calls exactly like SingleSignerValidationModule,
///         but on the secp256r1 curve instead of secp256k1
/// @dev This module provides WebAuthn-compatible signature validation using the P256 curve
contract P256ValidationModule is IP256ValidationModule, ReplaySafeWrapper, BaseModule {
    using MessageHashUtils for bytes32;

    /* ───────────────────────── Constants ─────────────────────────────── */
    /// @notice Return value indicating successful signature validation
    uint256 internal constant _SIG_VALIDATION_PASSED = 0;

    /// @notice Return value indicating failed signature validation
    uint256 internal constant _SIG_VALIDATION_FAILED = 1;

    /// @notice Magic value for ERC-1271 signature validation
    bytes4 internal constant _1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice Invalid value for ERC-1271 signature validation
    bytes4 internal constant _1271_INVALID = 0xffffffff;

    /* ───────────────────────── Storage ───────────────────────────────── */
    /// @notice Mapping of entityId and account to their P-256 public key
    mapping(uint32 => mapping(address => P256PublicKey)) public passkeys;

    /* ───────────────────────  Admin helpers  ─────────────────────────── */
    /// @notice Replace the stored pass-key for msg.sender + entityId
    /// @param entityId The entityId for the account and the passkey
    /// @param newKey The new passkey to use for validation
    function transferPasskey(uint32 entityId, P256PublicKey memory newKey) external {
        _transferPasskey(entityId, newKey);
    }

    /* ───────────────────────  IERC6900Module  ────────────────────────── */
    /// @notice Get the module ID
    /// @return The module ID string
    function moduleId() external pure override returns (string memory) {
        return "erc6900.p256-validation-module.1.0.0";
    }

    /// @notice Initialize the module with the given data
    /// @dev data = abi.encode(uint32 entityId, P256PublicKey key)
    /// @param data The initialization data
    function onInstall(bytes calldata data) external override {
        (uint32 entityId, P256PublicKey memory key) = abi.decode(data, (uint32, P256PublicKey));
        _transferPasskey(entityId, key);
    }

    /// @notice Clean up the module with the given data
    /// @dev data = abi.encode(uint32 entityId)
    /// @param data The cleanup data
    function onUninstall(bytes calldata data) external override {
        uint32 entityId = abi.decode(data, (uint32));
        _transferPasskey(entityId, P256PublicKey({x: 0, y: 0}));
    }

    /* ─────────────────── IERC6900ValidationModule  ───────────────────── */
    /// @notice Validate a user operation
    /// @param entityId The entityId for the account and the passkey
    /// @param userOp The user operation to validate
    /// @param userOpHash The hash of the user operation
    /// @return Whether the user operation is valid
    function validateUserOp(uint32 entityId, PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        view
        override
        returns (uint256)
    {
        P256PublicKey memory key = passkeys[entityId][userOp.sender];

        bool ok = P256VerifierLib._verifyRawP256Signature(
            userOpHash, // already a 32-byte hash
            userOp.signature, // raw (r‖s) 64-byte sig
            key.x,
            key.y
        );

        return ok ? _SIG_VALIDATION_PASSED : _SIG_VALIDATION_FAILED;
    }

    /// @notice Validate a runtime call
    /// @param account The account making the call
    /// @param sender The address making the call
    function validateRuntime(
        address account,
        uint32,
        address sender,
        uint256,
        bytes calldata,
        bytes calldata
    ) external view override {
        // Authorised if caller is the account itself *or*
        // the call is forwarded by the EntryPoint (which uses CALL not DELEGATECALL).
        if (sender != address(this) && sender != account) {
            revert NotAuthorized();
        }
    }

    /// @notice Validate a signature
    /// @param account The account whose signature is being validated
    /// @param entityId The entityId for the account and the passkey
    /// @param messageHash The hash of the message being signed
    /// @param signature The signature to validate
    /// @return The magic value if the signature is valid, invalid value otherwise
    function validateSignature(
        address account,
        uint32 entityId,
        address,
        bytes32 messageHash,
        bytes calldata signature
    ) public view override returns (bytes4) {
        // Get the public key for this entity
        P256PublicKey memory key = passkeys[entityId][account];

        // Verify the signature
        bool isValid = P256VerifierLib._verifyRawP256Signature(
            messageHash,
            signature,
            key.x,
            key.y
        );

        return isValid ? _1271_MAGIC_VALUE : _1271_INVALID;
    }

    /* ───────────────────── supportsInterface  ────────────────────────── */
    /// @notice Check if the contract supports a specific interface
    /// @param id The interface ID to check
    /// @return Whether the interface is supported
    function supportsInterface(bytes4 id) public view override(BaseModule, IERC165) returns (bool) {
        return id == type(IERC6900ValidationModule).interfaceId || super.supportsInterface(id);
    }

    /* ──────────────────── Internal helper  ───────────────────────────── */
    /// @notice Internal function to transfer a passkey
    /// @param entityId The entityId for the account and the passkey
    /// @param newKey The new passkey to use for validation
    function _transferPasskey(uint32 entityId, P256PublicKey memory newKey) internal {
        P256PublicKey memory prev = passkeys[entityId][msg.sender];
        passkeys[entityId][msg.sender] = newKey;
        emit PasskeyTransferred(msg.sender, entityId, newKey, prev);
    }
}
