// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {ReferenceModularAccount} from "@erc6900/reference-implementation/account/ReferenceModularAccount.sol";
import {ValidationConfigLib} from "@erc6900/reference-implementation/libraries/ValidationConfigLib.sol";
import {P256PublicKey} from "../utils/Types.sol";

/// @notice Factory that deploys a **ReferenceModularAccount**
///         pre-loaded with the `P256ValidationModule`.
contract P256AccountFactory is Ownable {
    /* -------------------------------------------------------------------- */
    /*  Immutable params                                                    */
    /* -------------------------------------------------------------------- */
    IEntryPoint public immutable ENTRY_POINT;
    ReferenceModularAccount public immutable ACCOUNT_IMPL;
    bytes32 private immutable _PROXY_BYTECODE_HASH;
    address public immutable P256_VALIDATION_MODULE;

    event ModularAccountDeployed(address indexed account, bytes32 indexed passkeyHash, uint256 salt);

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
    /// @param salt        arbitrary salt that lets the user pre-compute addr.
    /// @param entityId    ERC-6900 entity namespace for the user’s key.
    /// @param passkey     raw secp256r1 public key `{x,y}` (same struct as lib).
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
    function addStake(uint32 unstakeDelay) external payable onlyOwner {
        ENTRY_POINT.addStake{value: msg.value}(unstakeDelay);
    }

    function unlockStake() external onlyOwner {
        ENTRY_POINT.unlockStake();
    }

    function withdrawStake(address payable to) external onlyOwner {
        ENTRY_POINT.withdrawStake(to);
    }
}
