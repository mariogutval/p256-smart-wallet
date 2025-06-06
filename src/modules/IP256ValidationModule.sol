// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC6900ValidationModule} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";
import {P256PublicKey} from "../utils/Types.sol";

interface IP256ValidationModule is IERC6900ValidationModule {
    /// @notice This event is emitted when Passkey of the account's validation changes.
    /// @param account The account whose validation Passkey changed.
    /// @param entityId The entityId for the account and the passkey.
    /// @param newKey The new passkey.
    /// @param previousKey The previous passkey.
    event PasskeyTransferred(
        address indexed account, uint32 indexed entityId, P256PublicKey indexed newKey, P256PublicKey previousKey
    ) anonymous;

    error NotAuthorized();

    /// @notice Transfer Passkey of the account's validation to `newKey`.
    /// @param entityId The entityId for the account and the passkey.
    /// @param newKey The new passkey.
    function transferPasskey(uint32 entityId, P256PublicKey memory newKey) external;
}
