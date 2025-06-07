// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Forge imports
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// ERC6900 imports
import {ReferenceModularAccount} from "@erc6900/reference-implementation/account/ReferenceModularAccount.sol";
import {
    ExecutionManifest,
    ManifestExecutionFunction,
    ManifestExecutionHook
} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";

// Account Abstraction imports
import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";

// Local imports
import {P256ValidationModule} from "../src/modules/P256ValidationModule.sol";
import {DCAModule} from "../src/modules/DCAModule.sol";
import {P256PublicKey} from "../src/utils/Types.sol";
import {P256AccountFactory} from "../src/factory/P256AccountFactory.sol";

contract P256AccountScript is Script {
    // Constants
    uint32 internal constant DEFAULT_ENTITY_ID = 1;

    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy EntryPoint (or use existing one)
        IEntryPoint entryPoint = IEntryPoint(vm.envAddress("ENTRY_POINT_ADDRESS"));

        // Deploy modules
        P256ValidationModule validationModule = new P256ValidationModule();
        DCAModule dcaModule = new DCAModule();

        // Deploy account implementation
        ReferenceModularAccount accountImpl = new ReferenceModularAccount(entryPoint);

        // Deploy factory
        P256AccountFactory factory = new P256AccountFactory(
            entryPoint,
            accountImpl,
            address(validationModule),
            msg.sender // admin
        );

        // Get passkey from environment
        uint256 x = vm.envUint("PASSKEY_X");
        uint256 y = vm.envUint("PASSKEY_Y");
        P256PublicKey memory passkey = P256PublicKey({x: x, y: y});

        // Deploy account
        uint256 salt = vm.envUint("SALT");
        ReferenceModularAccount account = factory.createAccount(salt, DEFAULT_ENTITY_ID, passkey);

        // Prepare DCA module manifest
        ManifestExecutionFunction[] memory functions = new ManifestExecutionFunction[](5);
        functions[0] = ManifestExecutionFunction({
            executionSelector: dcaModule.createPlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });
        functions[1] = ManifestExecutionFunction({
            executionSelector: dcaModule.executePlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });
        functions[2] = ManifestExecutionFunction({
            executionSelector: dcaModule.cancelPlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });
        functions[3] = ManifestExecutionFunction({
            executionSelector: dcaModule.whitelistDex.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });
        functions[4] = ManifestExecutionFunction({
            executionSelector: dcaModule.unwhitelistDex.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });

        // Install DCA module
        account.installExecution(
            address(dcaModule),
            ExecutionManifest({
                executionFunctions: functions,
                executionHooks: new ManifestExecutionHook[](0),
                interfaceIds: new bytes4[](0)
            }),
            ""
        );

        // Log deployed addresses
        console2.log("Deployed addresses:");
        console2.log("Validation Module:", address(validationModule));
        console2.log("DCA Module:", address(dcaModule));
        console2.log("Account Implementation:", address(accountImpl));
        console2.log("Factory:", address(factory));
        console2.log("Account:", address(account));

        vm.stopBroadcast();
    }
}
