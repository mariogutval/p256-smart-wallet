// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {P256VerifierLib} from "../../src/libraries/P256VerifierLib.sol";
import {P256SCLVerifierLib} from "../../src/libraries/P256SCLVerifierLib.sol";
import { Vm } from "forge-std/Vm.sol";

library SigningUtilsLib {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant P256_N = 115792089210356248762697446949407573529996955224135760342422259061068512044369;

    /// @notice Sign a *32-byte* digest so that P256ValidationModule will accept it.
    function signHashP256(uint256 privKey, bytes32 digest) internal pure returns (bytes memory sig) {
        // The verifier checks signatures over `sha256(digest)`, hence we pre-hash here so that
        // `vm.signP256` signs the correct message.
        digest = sha256(abi.encodePacked(digest));

        (bytes32 r, bytes32 s) = vm.signP256(privKey, digest);

        if (uint256(s) > P256SCLVerifierLib.P256_N_DIV_2) {
            s = bytes32(P256_N - uint256(s));
        }

        // Raw r‖s, 64-byte, little-endian as the verifier expects.
        sig = abi.encodePacked(r, s);
    }
}
