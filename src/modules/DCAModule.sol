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
import {IERC165}          from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20}           from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}        from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* ───── Types ─────────────────────────────────────────────────────────── */
struct DCAPlan {
    address tokenIn;
    address tokenOut;
    uint256 amount;        // tokens per interval
    uint256 interval;      // seconds
    uint256 nextExec;      // timestamp
    bool    active;
}

/* ───────────────────────── Module ────────────────────────────────────── */
/// @title  DCA Execution Module (ERC-6900)
/// @author Community
/// @notice Stores recurring swap plans inside the smart-wallet’s storage and
///         executes them through whitelisted DEX routers.
contract DCAModule is IERC6900ExecutionModule, BaseModule {
    using SafeERC20 for IERC20;

    /* ─────────────────── Storage (plain mappings) ────────────────────── */
    uint256 internal _planCount;
    mapping(uint256 id => DCAPlan)         internal _plans;
    mapping(address dex => bool whitelisted) public dexWhitelist;

    /* ─────────────────── Re-entrancy guard ───────────────────────────── */
    uint256 private _lock;
    modifier nonReentrant() {
        require(_lock == 0, "DCA: re-entrancy");
        _lock = 1;
        _;
        _lock = 0;
    }

    /* ───────────────────── Events ────────────────────────────────────── */
    event PlanCreated  (uint256 indexed id, address tokenIn, address tokenOut);
    event PlanExecuted (uint256 indexed id);
    event PlanCancelled(uint256 indexed id);

    /* ───────────────────── Public API  ───────────────────────────────── */

    /// Create a new DCA plan.
    function createPlan(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 everySeconds
    )
        external
        returns (uint256 id)
    {
        id = ++_planCount;
        _plans[id] = DCAPlan({
            tokenIn:   tokenIn,
            tokenOut:  tokenOut,
            amount:    amount,
            interval:  everySeconds,
            nextExec:  block.timestamp + everySeconds,
            active:    true
        });
        emit PlanCreated(id, tokenIn, tokenOut);
    }

    /// Execute a plan via a whitelisted router (`swapData` must spend `amount` once).
    function executePlan(
        uint256 id,
        address dexRouter,
        bytes calldata swapData
    )
        external
        nonReentrant
    {
        DCAPlan storage p = _plans[id];

        require(p.active,               "DCA: inactive");
        require(block.timestamp >= p.nextExec, "DCA: too early");
        require(dexWhitelist[dexRouter],        "DCA: DEX not whitelisted");

        // Approve router to pull `amount`
        IERC20(p.tokenIn).safeIncreaseAllowance(dexRouter, p.amount);

        // Execute low-level swap on router
        (bool ok, bytes memory ret) = dexRouter.call(swapData);
        require(ok, string(ret));

        // Schedule next window
        p.nextExec = block.timestamp + p.interval;
        emit PlanExecuted(id);
    }

    /// Cancel a plan permanently.
    function cancelPlan(uint256 id) external {
        _plans[id].active = false;
        emit PlanCancelled(id);
    }

    /// Manage router allow-list.
    function whitelistDex(address dex)     external { dexWhitelist[dex] = true; }
    function unwhitelistDex(address dex)   external { dexWhitelist[dex] = false; }

    /* ─────────────────── IERC6900Module surface  ─────────────────────── */

    /// @dev Execution-only module – not a validator.
    function onInstall(bytes calldata) external override { /* no-op */ }
    function onUninstall(bytes calldata) external override { /* no-op */ }

    function moduleId() external pure override returns (string memory) {
        return "erc6900.dca-execution-module.1.0.0";
    }

    /// Return the function selectors this module owns (needed by the account).
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
    function executionManifest() external pure override returns (ExecutionManifest memory m) {
        // 1. execution selectors -----------------------------------
        m.executionFunctions = new ManifestExecutionFunction[](5);

        m.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: DCAModule.createPlan.selector,
            skipRuntimeValidation: false,       // must be authorised
            allowGlobalValidation:  true        // let the account’s global runtime-validator check it
        });

        m.executionFunctions[1] = ManifestExecutionFunction({
            executionSelector: DCAModule.executePlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation:  true
        });

        m.executionFunctions[2] = ManifestExecutionFunction({
            executionSelector: DCAModule.cancelPlan.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation:  true
        });

        m.executionFunctions[3] = ManifestExecutionFunction({
            executionSelector: DCAModule.whitelistDex.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation:  true
        });

        m.executionFunctions[4] = ManifestExecutionFunction({
            executionSelector: DCAModule.unwhitelistDex.selector,
            skipRuntimeValidation: false,
            allowGlobalValidation:  true
        });

        // 2. hooks --------------------------------------------------
        // This module has no pre- or post-execution hooks.
        m.executionHooks = new ManifestExecutionHook[](0);

        // 3. interface IDs -----------------------------------------
        // Nothing extra to expose via ERC-165
        m.interfaceIds = new bytes4[](0);
    }


    /* ───────────── supportsInterface (ERC-165) ───────────────────────── */
    function supportsInterface(bytes4 id)
        public
        view
        override(BaseModule, IERC165)
        returns (bool)
    {
        return id == type(IERC6900ExecutionModule).interfaceId
            || super.supportsInterface(id);
    }
}