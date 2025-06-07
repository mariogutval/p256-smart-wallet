// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {ReferenceModularAccount} from "@erc6900/reference-implementation/account/ReferenceModularAccount.sol";
import {ValidationConfigLib} from "@erc6900/reference-implementation/libraries/ValidationConfigLib.sol";
import {P256PublicKey} from "../utils/Types.sol";

/// @title P256AccountFactory
/// @notice Factory that deploys a ReferenceModularAccount pre-loaded with the P256ValidationModule
/// @dev This factory creates accounts with P256 validation module pre-installed and handles EntryPoint staking
contract P256AccountFactory is Ownable {
    /* -------------------------------------------------------------------- */
    /*  Immutable params                                                    */
    /* -------------------------------------------------------------------- */
    /// @notice The EntryPoint contract used for account abstraction
    IEntryPoint public immutable ENTRY_POINT;

    /// @notice The implementation of the modular account
    ReferenceModularAccount public immutable ACCOUNT_IMPL;

    /// @notice The hash of the proxy bytecode for deterministic address computation
    bytes32 private immutable _PROXY_BYTECODE_HASH;

    /// @notice The address of the P256 validation module
    address public immutable P256_VALIDATION_MODULE;

    /// @notice Emitted when a new modular account is deployed
    /// @param account The address of the deployed account
    /// @param passkeyHash The hash of the passkey used for validation
    /// @param salt The salt used for deterministic address computation
    event ModularAccountDeployed(address indexed account, bytes32 indexed passkeyHash, uint256 salt);

    /// @notice Creates a new factory with the given parameters
    /// @param _entryPoint The EntryPoint contract
    /// @param _accountImpl The implementation of the modular account
    /// @param _p256ValidationModule The address of the P256 validation module
    /// @param factoryOwner The owner of the factory contract
    constructor(
        IEntryPoint _entryPoint,
        ReferenceModularAccount _accountImpl,
        address _p256ValidationModule,
        address factoryOwner
    ) Ownable(factoryOwner) {
        ENTRY_POINT = _entryPoint;
        ACCOUNT_IMPL = _accountImpl;
        P256_VALIDATION_MODULE = _p256ValidationModule;

        _PROXY_BYTECODE_HASH =
            keccak256(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(_accountImpl), "")));
    }

    /* -------------------------------------------------------------------- */
    /*  Deploy or return a counterfactual address                            */
    /* -------------------------------------------------------------------- */
    /// @notice Creates a new modular account or returns an existing one
    /// @param salt Arbitrary salt that lets the user pre-compute address
    /// @param entityId ERC-6900 entity namespace for the user's key
    /// @param passkey Raw secp256r1 public key {x,y}
    /// @return wallet The deployed or existing modular account
    function createAccount(uint256 salt, uint32 entityId, P256PublicKey calldata passkey)
        external
        returns (ReferenceModularAccount wallet)
    {
        bytes32 combinedSalt = keccak256(abi.encodePacked(msg.sender, salt, entityId));
        address predicted = Create2.computeAddress(combinedSalt, _PROXY_BYTECODE_HASH);

        if (predicted.code.length == 0) {
            // 1. deploy minimal proxy
            new ERC1967Proxy{salt: combinedSalt}(address(ACCOUNT_IMPL), "");

            // 2. init the validation module (installs pass-key)
            bytes memory pluginData = abi.encode(entityId, passkey);
            ReferenceModularAccount(payable(predicted)).initializeWithValidation(
                ValidationConfigLib.pack(
                    P256_VALIDATION_MODULE,
                    entityId,
                    true, /* enable ERC-1271       */
                    true, /* enable isValidation() */
                    true /* enable hooks          */
                ),
                new bytes4[](0), // no selectors at install-time
                pluginData,
                new bytes[](0) // no hooks
            );

            emit ModularAccountDeployed(predicted, keccak256(abi.encode(passkey.x, passkey.y)), salt);
        }
        return ReferenceModularAccount(payable(predicted));
    }

    /* ------------------------- EntryPoint stake helpers ------------------ */
    /// @notice Adds stake to the EntryPoint contract
    /// @param unstakeDelay The delay before stake can be withdrawn
    function addStake(uint32 unstakeDelay) external payable onlyOwner {
        ENTRY_POINT.addStake{value: msg.value}(unstakeDelay);
    }

    /// @notice Unlocks the stake in the EntryPoint contract
    function unlockStake() external onlyOwner {
        ENTRY_POINT.unlockStake();
    }

    /// @notice Withdraws the stake from the EntryPoint contract
    /// @param to The address to receive the withdrawn stake
    function withdrawStake(address payable to) external onlyOwner {
        ENTRY_POINT.withdrawStake(to);
    }
}
