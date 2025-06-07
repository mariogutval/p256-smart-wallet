// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ERC6900 imports
import {ReferenceModularAccount} from "@erc6900/reference-implementation/account/ReferenceModularAccount.sol";
import {PackedUserOperation} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";
import {ExecutionManifest, ManifestExecutionFunction, ManifestExecutionHook} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";

// Account Abstraction imports
import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";

// FCL imports
import {FCL_ecdsa_utils} from "@FCL/FCL_ecdsa_utils.sol";

// Local imports
import {BaseTest} from "../helpers/BaseTest.sol";
import {P256ValidationModule} from "../../src/modules/P256ValidationModule.sol";
import {DCAModule} from "../../src/modules/DCAModule.sol";
import {P256PublicKey} from "../../src/utils/Types.sol";
import {P256AccountFactory} from "../../src/factory/P256AccountFactory.sol";
import {SigningUtilsLib} from "../helpers/SigningUtilsLib.sol";
import {MockERC20, MockDEXRouter, MockEntryPoint} from "../helpers/MockContracts.sol";

contract P256AccountTest is BaseTest {
    P256ValidationModule public validationModule;
    DCAModule public dcaModule;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockDEXRouter public dexRouter;
    P256AccountFactory public factory;
    ReferenceModularAccount public account;
    TestUser public testUser;
    P256PublicKey public testPasskey;
    IEntryPoint public entryPoint;

    event ModularAccountDeployed(address indexed account, bytes32 indexed passkeyHash, uint256 salt);

    function setUp() public {
        // Deploy EntryPoint
        entryPoint = new MockEntryPoint();

        // Deploy modules
        validationModule = new P256ValidationModule();
        dcaModule = new DCAModule();

        // Deploy tokens and DEX
        tokenIn = new MockERC20("Token In", "TIN");
        tokenOut = new MockERC20("Token Out", "TOUT");
        dexRouter = new MockDEXRouter();

        // Create test user and generate P-256 key pair
        testUser = createUser("testUser");
        testPasskey = createP256Key(testUser.privateKey);

        // Deploy account implementation
        ReferenceModularAccount accountImpl = new ReferenceModularAccount(entryPoint);

        // Deploy factory
        factory = new P256AccountFactory(
            entryPoint,
            accountImpl,
            address(validationModule),
            address(this)
        );

        // Whitelist DEX
        dcaModule.whitelistDex(address(dexRouter));

        // Mint tokens to test user
        tokenIn.mint(testUser.addr, 1000 ether);
    }

    function test_DeployAccount() public {
        vm.startPrank(testUser.addr);

        // Deploy account through factory
        uint256 salt = 123;

        // Deploy account first to get its address
        account = factory.createAccount(salt, DEFAULT_ENTITY_ID, testPasskey);

        // Verify account was deployed
        assertTrue(address(account) != address(0), "Account not deployed");

        // Fund the account
        vm.deal(address(account), 100 ether);

        vm.stopPrank();
    }

    function test_InstallModules() public {
        // Step 1: deploy account through factory (by the user)
        vm.prank(testUser.addr);
        account = factory.createAccount(123, DEFAULT_ENTITY_ID, testPasskey);

        // Step 2: prepare execution manifest for the DCA module (5 selectors)
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

        // Step 3: call installExecution from the EntryPoint (bypasses native validation)
        vm.prank(address(entryPoint));
        account.installExecution(
            address(dcaModule),
            ExecutionManifest({
                executionFunctions: functions,
                executionHooks: new ManifestExecutionHook[](0),
                interfaceIds: new bytes4[](0)
            }),
            ""
        );
    }

    function test_CreateAndExecuteDCAPlan() public {
        vm.startPrank(testUser.addr);

        // Deploy account
        account = factory.createAccount(123, DEFAULT_ENTITY_ID, testPasskey);

        // Create execution manifest with DCA module functions
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

        vm.stopPrank(); // Stop user prank before EntryPoint prank

        // Install DCAModule via EntryPoint
        vm.prank(address(entryPoint));
        account.installExecution(
            address(dcaModule),
            ExecutionManifest({
                executionFunctions: functions,
                executionHooks: new ManifestExecutionHook[](0),
                interfaceIds: new bytes4[](0)
            }),
            ""
        );

        // Create DCA plan
        vm.startPrank(testUser.addr); // Resume user prank for DCA operations
        uint256 amount = 100 ether;
        uint256 interval = 1 days;
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), amount, interval);

        // Approve tokens for DCA module
        tokenIn.approve(address(dcaModule), amount);

        // Fast forward time
        vm.warp(block.timestamp + interval);

        // Create and sign user operation
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");
        bytes memory executePlanData = abi.encodeWithSelector(
            dcaModule.executePlan.selector,
            planId,
            address(dexRouter),
            swapData
        );

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: abi.encodeCall(
                ReferenceModularAccount.execute,
                (address(dcaModule), 0, executePlanData)
            ),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: bytes("")
        });

        // Get userOpHash from EntryPoint
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);

        // Sign the userOpHash with P-256
        bytes memory signature = SigningUtilsLib.signHashP256(testUser.privateKey, userOpHash);

        // Encode signature in the format expected by P256ValidationModule
        // The signature should be wrapped with the validation module and entity ID
        bytes memory encodedSignature = abi.encodePacked(
            address(validationModule), // validation module address
            uint32(DEFAULT_ENTITY_ID), // entity ID  
            uint8(0), // validation mode (global validation)
            signature // actual P256 signature
        );

        // Update userOp with signature
        userOp.signature = encodedSignature;

        vm.stopPrank(); // Stop user prank before EntryPoint prank

        // Execute DCA plan through EntryPoint
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        entryPoint.handleOps(userOps, payable(address(this)));
    }

    function test_UninstallModules() public {
        vm.startPrank(testUser.addr);

        // Deploy account
        account = factory.createAccount(123, DEFAULT_ENTITY_ID, testPasskey);

        // Create execution manifest with DCA module functions
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

        vm.stopPrank(); // Stop user prank before EntryPoint prank

        // Install DCAModule via EntryPoint
        vm.prank(address(entryPoint));
        account.installExecution(
            address(dcaModule),
            ExecutionManifest({
                executionFunctions: functions,
                executionHooks: new ManifestExecutionHook[](0),
                interfaceIds: new bytes4[](0)
            }),
            ""
        );

        // Uninstall DCAModule via EntryPoint
        vm.prank(address(entryPoint));
        account.uninstallExecution(
            address(dcaModule),
            ExecutionManifest({
                executionFunctions: functions,
                executionHooks: new ManifestExecutionHook[](0),
                interfaceIds: new bytes4[](0)
            }),
            ""
        );
    }
}
