// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin imports
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

// ERC6900 imports
import {IERC6900ExecutionModule, ExecutionManifest} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";

// Local imports
import {BaseTest} from "../helpers/BaseTest.sol";
import {DCAModule} from "../../src/modules/DCAModule.sol";
import {IDCAModule} from "../../src/modules/IDCAModule.sol";
import {MockERC20, MockDEXRouter} from "../helpers/BaseTest.sol";

contract DCAModuleTest is BaseTest {
    DCAModule public dcaModule;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockDEXRouter public dexRouter;
    TestUser public testUser;

    event PlanCreated(uint256 indexed id, address tokenIn, address tokenOut);
    event PlanExecuted(uint256 indexed id);
    event PlanCancelled(uint256 indexed id);
    event DexWhitelisted(address indexed dex);
    event DexUnwhitelisted(address indexed dex);

    function setUp() public {
        dcaModule = new DCAModule();
        tokenIn = new MockERC20("Token In", "TIN");
        tokenOut = new MockERC20("Token Out", "TOUT");
        dexRouter = new MockDEXRouter();
        testUser = createUser("testUser");

        // Whitelist the DEX router
        dcaModule.whitelistDex(address(dexRouter));

        // Mint some tokens to test account
        tokenIn.mint(testUser.addr, 1000 ether);
    }

    function test_CreatePlan() public {
        vm.startPrank(testUser.addr);

        // Create a DCA plan
        uint256 amount = 100 ether;
        uint256 interval = 1 days;

        vm.expectEmit(true, false, false, true);
        emit PlanCreated(1, address(tokenIn), address(tokenOut));

        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), amount, interval);

        assertEq(planId, 1);

        vm.stopPrank();
    }

    function test_ExecutePlan() public {
        vm.startPrank(testUser.addr);

        // Create a DCA plan
        uint256 amount = 100 ether;
        uint256 interval = 1 days;
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), amount, interval);

        // Approve tokens for the module
        tokenIn.approve(address(dcaModule), amount);

        // Fast forward time to allow execution
        vm.warp(block.timestamp + interval);

        // Execute the plan
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectEmit(true, false, false, false);
        emit PlanExecuted(planId);

        dcaModule.executePlan(planId, address(dexRouter), swapData);

        vm.stopPrank();
    }

    function test_CancelPlan() public {
        vm.startPrank(testUser.addr);

        // Create a DCA plan
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);

        // Cancel the plan
        vm.expectEmit(true, false, false, false);
        emit PlanCancelled(planId);

        dcaModule.cancelPlan(planId);

        vm.stopPrank();
    }

    function test_ExecutePlan_NotWhitelisted() public {
        vm.startPrank(testUser.addr);

        // Create a DCA plan
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);

        // Fast forward time to allow execution
        vm.warp(block.timestamp + 1 days);

        // Try to execute with non-whitelisted router
        address nonWhitelistedRouter = makeAddr("nonWhitelisted");
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectRevert(abi.encodeWithSelector(IDCAModule.DexNotWhitelisted.selector));
        dcaModule.executePlan(planId, nonWhitelistedRouter, swapData);

        vm.stopPrank();
    }

    function test_ExecutePlan_TooEarly() public {
        vm.startPrank(testUser.addr);

        // Create a DCA plan with 1 day interval
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);

        // Try to execute immediately
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectRevert(abi.encodeWithSelector(IDCAModule.TooEarly.selector));
        dcaModule.executePlan(planId, address(dexRouter), swapData);

        vm.stopPrank();
    }

    function test_ExecutePlan_Inactive() public {
        vm.startPrank(testUser.addr);

        // Create and immediately cancel a plan
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);
        dcaModule.cancelPlan(planId);

        // Try to execute cancelled plan
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectRevert(abi.encodeWithSelector(IDCAModule.PlanInactive.selector));
        dcaModule.executePlan(planId, address(dexRouter), swapData);

        vm.stopPrank();
    }

    function test_WhitelistDex() public {
        address newDex = makeAddr("newDex");

        vm.expectEmit(true, false, false, false);
        emit DexWhitelisted(newDex);
        dcaModule.whitelistDex(newDex);
        assertTrue(dcaModule.dexWhitelist(newDex));
    }

    function test_UnwhitelistDex() public {
        address dex = makeAddr("dex");

        dcaModule.whitelistDex(dex);
        vm.expectEmit(true, false, false, false);
        emit DexUnwhitelisted(dex);
        dcaModule.unwhitelistDex(dex);
        assertFalse(dcaModule.dexWhitelist(dex));
    }

    function test_ModuleId() public view {
        string memory id = dcaModule.moduleId();
        assertEq(id, "erc6900.dca-execution-module.1.0.0");
    }

    function test_SupportsInterface() public view {
        // Test ERC165 interface support
        assertTrue(dcaModule.supportsInterface(0x01ffc9a7)); // IERC165
        // IERC6900ExecutionModule interface id
        bytes4 erc6900Id = type(IERC6900ExecutionModule).interfaceId;
        assertTrue(dcaModule.supportsInterface(erc6900Id));
        // IDCAModule interface id
        bytes4 dcaId = type(IDCAModule).interfaceId;
        assertTrue(dcaModule.supportsInterface(dcaId));
        assertFalse(dcaModule.supportsInterface(0xffffffff)); // Random interface
    }

    function test_Selectors() public view {
        bytes4[] memory selectors = dcaModule.selectors();
        assertEq(selectors.length, 5);
        assertEq(selectors[0], dcaModule.createPlan.selector);
        assertEq(selectors[1], dcaModule.executePlan.selector);
        assertEq(selectors[2], dcaModule.cancelPlan.selector);
        assertEq(selectors[3], dcaModule.whitelistDex.selector);
        assertEq(selectors[4], dcaModule.unwhitelistDex.selector);
    }

    function test_ExecutionManifest() public view {
        ExecutionManifest memory manifest = dcaModule.executionManifest();

        // Check execution functions
        assertEq(manifest.executionFunctions.length, 5);
        
        // Check createPlan
        assertEq(manifest.executionFunctions[0].executionSelector, dcaModule.createPlan.selector);
        assertFalse(manifest.executionFunctions[0].skipRuntimeValidation);
        assertTrue(manifest.executionFunctions[0].allowGlobalValidation);

        // Check executePlan
        assertEq(manifest.executionFunctions[1].executionSelector, dcaModule.executePlan.selector);
        assertFalse(manifest.executionFunctions[1].skipRuntimeValidation);
        assertTrue(manifest.executionFunctions[1].allowGlobalValidation);

        // Check cancelPlan
        assertEq(manifest.executionFunctions[2].executionSelector, dcaModule.cancelPlan.selector);
        assertFalse(manifest.executionFunctions[2].skipRuntimeValidation);
        assertTrue(manifest.executionFunctions[2].allowGlobalValidation);

        // Check whitelistDex
        assertEq(manifest.executionFunctions[3].executionSelector, dcaModule.whitelistDex.selector);
        assertFalse(manifest.executionFunctions[3].skipRuntimeValidation);
        assertTrue(manifest.executionFunctions[3].allowGlobalValidation);

        // Check unwhitelistDex
        assertEq(manifest.executionFunctions[4].executionSelector, dcaModule.unwhitelistDex.selector);
        assertFalse(manifest.executionFunctions[4].skipRuntimeValidation);
        assertTrue(manifest.executionFunctions[4].allowGlobalValidation);

        // Check hooks (should be empty)
        assertEq(manifest.executionHooks.length, 0);

        // Check interface IDs (should be empty)
        assertEq(manifest.interfaceIds.length, 0);
    }

    function test_OnInstall() public {
        // onInstall is a no-op, but we should test it doesn't revert
        bytes memory installData = "";
        dcaModule.onInstall(installData);
    }

    function test_OnUninstall() public {
        // onUninstall is a no-op, but we should test it doesn't revert
        bytes memory uninstallData = "";
        dcaModule.onUninstall(uninstallData);
    }

    function test_CreatePlan_InvalidAmount() public {
        vm.startPrank(testUser.addr);
        vm.expectRevert(abi.encodeWithSelector(IDCAModule.InvalidAmount.selector));
        dcaModule.createPlan(address(tokenIn), address(tokenOut), 0, 1 days);
        vm.stopPrank();
    }

    function test_CreatePlan_InvalidInterval() public {
        vm.startPrank(testUser.addr);
        vm.expectRevert(abi.encodeWithSelector(IDCAModule.InvalidInterval.selector));
        dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 0);
        vm.stopPrank();
    }
}
