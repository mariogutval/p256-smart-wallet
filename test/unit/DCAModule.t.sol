// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DCAModule} from "../../src/modules/DCAModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6900ExecutionModule} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
}

contract MockDEXRouter {
    function swap(bytes calldata) external returns (bool) {
        return true;
    }
}

contract DCAModuleTest is Test {
    DCAModule public dcaModule;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockDEXRouter public dexRouter;
    address public testAccount;

    event PlanCreated(uint256 indexed id, address tokenIn, address tokenOut);
    event PlanExecuted(uint256 indexed id);
    event PlanCancelled(uint256 indexed id);

    function setUp() public {
        dcaModule = new DCAModule();
        tokenIn = new MockERC20("Token In", "TIN");
        tokenOut = new MockERC20("Token Out", "TOUT");
        dexRouter = new MockDEXRouter();
        testAccount = makeAddr("testAccount");

        // Whitelist the DEX router
        dcaModule.whitelistDex(address(dexRouter));

        // Mint some tokens to test account
        tokenIn.mint(testAccount, 1000 ether);
    }

    function test_CreatePlan() public {
        vm.startPrank(testAccount);

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
        vm.startPrank(testAccount);

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
        vm.startPrank(testAccount);

        // Create a DCA plan
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);

        // Cancel the plan
        vm.expectEmit(true, false, false, false);
        emit PlanCancelled(planId);

        dcaModule.cancelPlan(planId);

        vm.stopPrank();
    }

    function test_ExecutePlan_NotWhitelisted() public {
        vm.startPrank(testAccount);

        // Create a DCA plan
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);

        // Fast forward time to allow execution
        vm.warp(block.timestamp + 1 days);

        // Try to execute with non-whitelisted router
        address nonWhitelistedRouter = makeAddr("nonWhitelisted");
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectRevert("DCA: DEX not whitelisted");
        dcaModule.executePlan(planId, nonWhitelistedRouter, swapData);

        vm.stopPrank();
    }

    function test_ExecutePlan_TooEarly() public {
        vm.startPrank(testAccount);

        // Create a DCA plan with 1 day interval
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);

        // Try to execute immediately
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectRevert("DCA: too early");
        dcaModule.executePlan(planId, address(dexRouter), swapData);

        vm.stopPrank();
    }

    function test_ExecutePlan_Inactive() public {
        vm.startPrank(testAccount);

        // Create and immediately cancel a plan
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), 100 ether, 1 days);
        dcaModule.cancelPlan(planId);

        // Try to execute cancelled plan
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");

        vm.expectRevert("DCA: inactive");
        dcaModule.executePlan(planId, address(dexRouter), swapData);

        vm.stopPrank();
    }

    function test_WhitelistDex() public {
        address newDex = makeAddr("newDex");

        dcaModule.whitelistDex(newDex);
        assertTrue(dcaModule.dexWhitelist(newDex));
    }

    function test_UnwhitelistDex() public {
        address dex = makeAddr("dex");

        dcaModule.whitelistDex(dex);
        dcaModule.unwhitelistDex(dex);
        assertFalse(dcaModule.dexWhitelist(dex));
    }

    function test_ModuleId() public {
        string memory id = dcaModule.moduleId();
        assertEq(id, "erc6900.dca-execution-module.1.0.0");
    }

    function test_SupportsInterface() public {
        // Test ERC165 interface support
        assertTrue(dcaModule.supportsInterface(0x01ffc9a7)); // IERC165
        // IERC6900ExecutionModule interface id
        bytes4 erc6900Id = type(IERC6900ExecutionModule).interfaceId;
        assertTrue(dcaModule.supportsInterface(erc6900Id));
        assertFalse(dcaModule.supportsInterface(0xffffffff)); // Random interface
    }

    function test_Selectors() public {
        bytes4[] memory selectors = dcaModule.selectors();
        assertEq(selectors.length, 5);
        assertEq(selectors[0], dcaModule.createPlan.selector);
        assertEq(selectors[1], dcaModule.executePlan.selector);
        assertEq(selectors[2], dcaModule.cancelPlan.selector);
        assertEq(selectors[3], dcaModule.whitelistDex.selector);
        assertEq(selectors[4], dcaModule.unwhitelistDex.selector);
    }
}
