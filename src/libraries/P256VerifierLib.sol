// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.20;

import {P256SCLVerifierLib} from "./P256SCLVerifierLib.sol";

/**
 * @title P256VerifierLib
 * @notice Provides functionality to decode P256 signatures into their components
 * @dev This library wraps Daimo's Progressive Precompile P256 Verifier
 */
library P256VerifierLib {
    /**
     * @notice Decodes a raw P256 signature and verifies it against the provided hash using a progressive precompile P256 verifier
     * @dev Raw P256 signatures encode: r, s
     * @param _hash The hash to be verified
     * @param _signature The signature to be verified
     * @param _x The X coordinate of the public key that signed the message
     * @param _y The Y coordinate of the public key that signed the message
     */
    function _verifyRawP256Signature(bytes32 _hash, bytes memory _signature, uint256 _x, uint256 _y)
        internal
        view
        returns (bool)
    {
        (uint256 r_, uint256 s_) = _decodeRawP256Signature(_signature);
        bytes32 messageHash_ = sha256(abi.encodePacked(_hash));
        return P256SCLVerifierLib.verifySignature(messageHash_, r_, s_, _x, _y);
    }

    /**
     * @notice This function decodes a raw P256 signature
     * @dev The signature consists of: bytes32, uint256, uint256
     * @param _signature The signature to be decoded
     * @return r_ The r component of the signature
     * @return s_ The s component of the signature
     */
    function _decodeRawP256Signature(bytes memory _signature) internal pure returns (uint256 r_, uint256 s_) {
        (r_, s_) = abi.decode(_signature, (uint256, uint256));
    }
}
