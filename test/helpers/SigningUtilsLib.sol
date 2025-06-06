// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {P256VerifierLib} from "../../src/libraries/P256VerifierLib.sol";
import { Vm } from "forge-std/Vm.sol";

library SigningUtilsLib {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant P256_N = 115792089210356248762697446949407573529996955224135760342422259061068512044369;

    /// @notice Sign a *32-byte* digest so that P256ValidationModule will accept it.
    function signHashP256(uint256 privKey, bytes32 digest) internal pure returns (bytes memory sig) {
        // vm.signP256 already expects the *message*.
        (bytes32 r, bytes32 s) = vm.signP256(privKey, digest);

        // Low-s canonisation (module does it internally, but harmless here)
        if (uint256(s) > (P256_N >> 1)) {
            s = bytes32(P256_N - uint256(s));
        }

        // Raw r‖s, 64-byte, little-endian as the verifier expects.
        sig = abi.encodePacked(r, s);
    }
}
