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
/// @author  ERC-6900 community
/// @notice  Validation module that stores **one P-256 pass-key per
///          (account, entityId)** and validates signatures & runtime calls
///          exactly like `SingleSignerValidationModule`, but on the secp256r1
///          curve instead of secp256k1.
contract P256ValidationModule is IP256ValidationModule, ReplaySafeWrapper, BaseModule {
    using MessageHashUtils for bytes32;

    /* ───────────────────────── Constants ─────────────────────────────── */

    uint256 internal constant _SIG_VALIDATION_PASSED = 0;
    uint256 internal constant _SIG_VALIDATION_FAILED = 1;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant _1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _1271_INVALID = 0xffffffff;

    /* ───────────────────────── Storage ───────────────────────────────── */

    // entityId  →  account  →  P-256 public key
    mapping(uint32 => mapping(address => P256PublicKey)) public passkeys;

    /* ───────────────────────  Admin helpers  ─────────────────────────── */

    /// @notice Replace the stored pass-key for `msg.sender` + `entityId`.
    function transferPasskey(uint32 entityId, P256PublicKey memory newKey) external {
        _transferPasskey(entityId, newKey);
    }

    /* ───────────────────────  IERC6900Module  ────────────────────────── */

    function moduleId() external pure override returns (string memory) {
        return "erc6900.p256-validation-module.1.0.0";
    }

    /// @dev `data = abi.encode(uint32 entityId, P256PublicKey key)`
    function onInstall(bytes calldata data) external override {
        (uint32 entityId, P256PublicKey memory key) = abi.decode(data, (uint32, P256PublicKey));
        _transferPasskey(entityId, key);
    }

    /// @dev `data = abi.encode(uint32 entityId)`
    function onUninstall(bytes calldata data) external override {
        uint32 entityId = abi.decode(data, (uint32));
        _transferPasskey(entityId, P256PublicKey({x: 0, y: 0}));
    }

    /* ─────────────────── IERC6900ValidationModule  ───────────────────── */

    /// @inheritdoc IERC6900ValidationModule
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

    /// @inheritdoc IERC6900ValidationModule
    function validateRuntime(
        address account,
        uint32,
        address sender,
        uint256, /* value      – unused */
        bytes calldata, /* data       – unused */
        bytes calldata /* auth blob  – unused */
    ) external view override {
        // Authorised if caller is the account itself *or*
        // the call is forwarded by the EntryPoint (which uses CALL not DELEGATECALL).
        if (sender != address(this) && sender != account) {
            revert NotAuthorized();
        }
    }

    /// @inheritdoc IERC6900ValidationModule
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

    function supportsInterface(bytes4 id) public view override(BaseModule, IERC165) returns (bool) {
        return id == type(IERC6900ValidationModule).interfaceId || super.supportsInterface(id);
    }

    /* ──────────────────── Internal helper  ───────────────────────────── */

    function _transferPasskey(uint32 entityId, P256PublicKey memory newKey) internal {
        P256PublicKey memory prev = passkeys[entityId][msg.sender];
        passkeys[entityId][msg.sender] = newKey;
        emit PasskeyTransferred(msg.sender, entityId, newKey, prev);
    }
}
