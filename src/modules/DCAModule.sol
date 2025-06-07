// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ───── ERC-6900 core ─────────────────────────────────────────────────── */
import {
    IERC6900ExecutionModule,
    ExecutionManifest,
    ManifestExecutionFunction,
    ManifestExecutionHook
} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";
import {BaseModule} from "@erc6900/reference-implementation/modules/BaseModule.sol";

/* ───── OpenZeppelin helpers ──────────────────────────────────────────── */
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* ───── Local imports ─────────────────────────────────────────────────── */
import {IDCAModule} from "./IDCAModule.sol";

/* ───────────────────────── Module ────────────────────────────────────── */
/// @title DCA Execution Module (ERC-6900)
/// @author Community
/// @notice Stores recurring swap plans inside the smart-wallet's storage and
///         executes them through whitelisted DEX routers
/// @dev This module implements the IDCAModule interface and provides functionality
///      for creating and managing recurring token swap plans
contract DCAModule is IDCAModule, BaseModule {
    using SafeERC20 for IERC20;

    /* ─────────────────── Storage (plain mappings) ────────────────────── */
    /// @notice Counter for generating unique plan IDs
    uint256 internal _planCount;

    /// @notice Mapping of plan IDs to their details
    mapping(uint256 id => Plan) internal _plans;

    /// @notice Mapping of DEX router addresses to their whitelist status
    mapping(address dex => bool whitelisted) public override dexWhitelist;

    /* ─────────────────── Re-entrancy guard ───────────────────────────── */
    /// @notice Re-entrancy guard state
    uint256 private _lock;

    /// @notice Prevents re-entrancy attacks
    modifier nonReentrant() {
        require(_lock == 0, "DCA: re-entrancy");
        _lock = 1;
        _;
        _lock = 0;
    }

    /* ───────────────────── Public API  ───────────────────────────────── */

    /// @notice Create a new DCA plan
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amount The amount of input tokens to swap in each execution
    /// @param everySeconds The time interval between executions in seconds
    /// @return id The unique identifier of the created plan
    function createPlan(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 everySeconds
    ) external override returns (uint256 id) {
        if (amount == 0) revert InvalidAmount();
        if (everySeconds == 0) revert InvalidInterval();

        id = ++_planCount;
        _plans[id] = Plan({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amount: amount,
            interval: everySeconds,
            lastExecution: block.timestamp,
            active: true
        });
        emit PlanCreated(id, tokenIn, tokenOut);
    }

    /// @notice Execute a plan via a whitelisted router (`swapData` must spend `amount` once)
    /// @param id The unique identifier of the plan to execute
    /// @param dexRouter The address of the DEX router to use
    /// @param swapData The calldata for the swap operation
    function executePlan(
        uint256 id,
        address dexRouter,
        bytes calldata swapData
    ) external override nonReentrant {
        Plan storage p = _plans[id];

        if (!p.active) revert PlanInactive();
        if (block.timestamp < p.lastExecution + p.interval) revert TooEarly();
        if (!dexWhitelist[dexRouter]) revert DexNotWhitelisted();

        // Approve router to pull `amount`
        IERC20(p.tokenIn).safeIncreaseAllowance(dexRouter, p.amount);

        // Execute low-level swap on router
        (bool ok, bytes memory ret) = dexRouter.call(swapData);
        require(ok, string(ret));

        // Update last execution time
        p.lastExecution = block.timestamp;
        emit PlanExecuted(id);
    }

    /// @notice Cancel a plan permanently
    /// @param id The unique identifier of the plan to cancel
    function cancelPlan(uint256 id) external override {
        if (!_plans[id].active) revert PlanInactive();
        _plans[id].active = false;
        emit PlanCancelled(id);
    }

    /// @notice Manage router allow-list
    /// @param dex The address of the DEX router to whitelist
    function whitelistDex(address dex) external override {
        dexWhitelist[dex] = true;
        emit DexWhitelisted(dex);
    }

    /// @notice Remove a DEX router from the whitelist
    /// @param dex The address of the DEX router to remove
    function unwhitelistDex(address dex) external override {
        dexWhitelist[dex] = false;
        emit DexUnwhitelisted(dex);
    }

    /* ─────────────────── View functions ─────────────────────────────── */
    /// @notice Get the details of a DCA plan
    /// @param planId The unique identifier of the plan
    /// @return The plan details
    function plans(uint256 planId) external view override returns (Plan memory) {
        return _plans[planId];
    }

    /// @notice Get the next available plan ID
    /// @return The next plan ID
    function nextPlanId() external view override returns (uint256) {
        return _planCount + 1;
    }

    /* ─────────────────── IERC6900Module surface  ─────────────────────── */

    /// @notice Execution-only module – not a validator
    /// @dev No-op implementation as this is an execution module
    function onInstall(bytes calldata) external override { /* no-op */ }

    /// @notice Execution-only module – not a validator
    /// @dev No-op implementation as this is an execution module
    function onUninstall(bytes calldata) external override { /* no-op */ }

    /// @notice Get the module ID
    /// @return The module ID string
    function moduleId() external pure override returns (string memory) {
        return "erc6900.dca-execution-module.1.0.0";
    }

    /// @notice Return the function selectors this module owns (needed by the account)
    /// @return s Array of function selectors
    function selectors() external pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = this.createPlan.selector;
        s[1] = this.executePlan.selector;
        s[2] = this.cancelPlan.selector;
        s[3] = this.whitelistDex.selector;
        s[4] = this.unwhitelistDex.selector;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃ IERC6900ExecutionModule – mandatory manifest declaration    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
    /// @notice Get the execution manifest for this module
    /// @return m The execution manifest
    function executionManifest() external pure override returns (ExecutionManifest memory m) {
        // 1. execution selectors -----------------------------------
        m.executionFunctions = new ManifestExecutionFunction[](5);

        m.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: DCAModule.createPlan.selector,
            skipRuntimeValidation: false, // must be authorised
            allowGlobalValidation: true // let the account's global runtime-validator check it
        });

        m.executionFunctions[1] = ManifestExecutionFunction({
            executionSelector: DCAModule.executePlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });

        m.executionFunctions[2] = ManifestExecutionFunction({
            executionSelector: DCAModule.cancelPlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });

        m.executionFunctions[3] = ManifestExecutionFunction({
            executionSelector: DCAModule.whitelistDex.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });

        m.executionFunctions[4] = ManifestExecutionFunction({
            executionSelector: DCAModule.unwhitelistDex.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation: true
        });

        // 2. hooks --------------------------------------------------
        // This module has no pre- or post-execution hooks.
        m.executionHooks = new ManifestExecutionHook[](0);

        // 3. interface IDs -----------------------------------------
        // Nothing extra to expose via ERC-165
        m.interfaceIds = new bytes4[](0);
    }

    /* ───────────── supportsInterface (ERC-165) ───────────────────────── */
    /// @notice Check if the contract supports a specific interface
    /// @param id The interface ID to check
    /// @return Whether the interface is supported
    function supportsInterface(bytes4 id) public view override(BaseModule, IERC165) returns (bool) {
        return id == type(IERC6900ExecutionModule).interfaceId || 
               id == type(IDCAModule).interfaceId || 
               super.supportsInterface(id);
    }
}
