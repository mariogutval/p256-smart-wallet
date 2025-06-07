// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.20;

import {SCL_RIP7212} from "@SCL/lib/libSCL_RIP7212.sol";
import {ec_isOnCurve} from "@SCL/elliptic/SCL_ecOncurve.sol";
import {a, b, p, n} from "@SCL/fields/SCL_secp256r1.sol";

/// @title P256SCLVerifierLib
/// @notice Library for verifying P256 (secp256r1) signatures using the SCL (Secure Computation Library)
/// @dev This library provides functions to verify signatures using the RIP-7212 precompile when available
library P256SCLVerifierLib {
    /// @notice Half of the P256 curve order, used for signature malleability check
    uint256 constant P256_N_DIV_2 = n / 2;

    /// @notice The address of the RIP-7212 P256Verify precompile
    /// @dev As specified in the RIP-7212 specification
    address constant VERIFIER = address(0x100);

    /// @notice Checks if a given public key is valid on the P256 elliptic curve
    /// @param _x The X coordinate of the public key
    /// @param _y The Y coordinate of the public key
    /// @return Whether the public key is valid on the P256 elliptic curve
    function isValidPublicKey(uint256 _x, uint256 _y) internal pure returns (bool) {
        return ec_isOnCurve(p, a, b, _x, _y);
    }

    /// @notice Verifies a signature using the SCL optimizations
    /// @dev First attempts to use the RIP-7212 precompile, falls back to SCL implementation if not available
    /// @param message_hash The hash of the message to verify
    /// @param r The r component of the signature
    /// @param s The s component of the signature
    /// @param x The X coordinate of the public key that signed the message
    /// @param y The Y coordinate of the public key that signed the message
    /// @return Whether the signature is valid
    function verifySignature(bytes32 message_hash, uint256 r, uint256 s, uint256 x, uint256 y)
        internal
        view
        returns (bool)
    {
        // check for signature malleability
        if (s > P256_N_DIV_2) {
            return false;
        }

        bytes memory args = abi.encode(message_hash, r, s, x, y);

        // attempt to verify using the RIP-7212 precompiled contract
        (bool success, bytes memory ret) = VERIFIER.staticcall(args);

        // staticcall returns true when the precompile does not exist but the ret.length is 0.
        // an invalid signature gets validated twice, simulate this offchain to save gas.
        bool valid = ret.length > 0;
        if (success && valid) return abi.decode(ret, (uint256)) == 1;

        return SCL_RIP7212.verify(message_hash, r, s, x, y);
    }
}
