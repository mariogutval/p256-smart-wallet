// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Types
/// @notice Common type definitions used across the codebase
/// @dev This file contains shared type definitions to ensure consistency across the project

/// @notice Structure representing a P256 (secp256r1) public key
/// @dev Used for storing and passing P256 public keys throughout the system
/// @param x The X coordinate of the public key
/// @param y The Y coordinate of the public key
struct P256PublicKey {
    uint256 x;
    uint256 y;
}
