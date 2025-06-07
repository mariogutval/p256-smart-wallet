// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6900ExecutionModule} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";

/// @title IDCAModule
/// @notice Interface for the DCA (Dollar Cost Averaging) Execution Module
/// @dev This module allows users to create and manage recurring token swap plans through whitelisted DEX routers
interface IDCAModule is IERC165, IERC6900ExecutionModule {
    // Events
    /// @notice Emitted when a new DCA plan is created
    /// @param id The unique identifier of the plan
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    event PlanCreated(uint256 indexed id, address tokenIn, address tokenOut);

    /// @notice Emitted when a DCA plan is executed
    /// @param id The unique identifier of the plan
    event PlanExecuted(uint256 indexed id);

    /// @notice Emitted when a DCA plan is cancelled
    /// @param id The unique identifier of the plan
    event PlanCancelled(uint256 indexed id);

    /// @notice Emitted when a DEX router is added to the whitelist
    /// @param dex The address of the whitelisted DEX router
    event DexWhitelisted(address indexed dex);

    /// @notice Emitted when a DEX router is removed from the whitelist
    /// @param dex The address of the removed DEX router
    event DexUnwhitelisted(address indexed dex);

    // Errors
    /// @notice Error thrown when attempting to access a non-existent plan
    error PlanNotFound();

    /// @notice Error thrown when attempting to execute an inactive plan
    error PlanInactive();

    /// @notice Error thrown when attempting to use a non-whitelisted DEX router
    error DexNotWhitelisted();

    /// @notice Error thrown when attempting to execute a plan before its interval has elapsed
    error TooEarly();

    /// @notice Error thrown when attempting to create a plan with zero amount
    error InvalidAmount();

    /// @notice Error thrown when attempting to create a plan with zero interval
    error InvalidInterval();

    // Structs
    /// @notice Structure representing a DCA plan
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amount The amount of input tokens to swap in each execution
    /// @param interval The time interval between executions in seconds
    /// @param lastExecution The timestamp of the last execution
    /// @param active Whether the plan is currently active
    struct Plan {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint256 interval;
        uint256 lastExecution;
        bool active;
    }

    // Functions
    /// @notice Creates a new DCA plan
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amount The amount of input tokens to swap in each execution
    /// @param interval The time interval between executions in seconds
    /// @return planId The unique identifier of the created plan
    function createPlan(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 interval
    ) external returns (uint256 planId);

    /// @notice Executes a DCA plan through a whitelisted DEX router
    /// @param planId The unique identifier of the plan to execute
    /// @param dex The address of the DEX router to use
    /// @param swapData The calldata for the swap operation
    function executePlan(
        uint256 planId,
        address dex,
        bytes calldata swapData
    ) external;

    /// @notice Cancels an active DCA plan
    /// @param planId The unique identifier of the plan to cancel
    function cancelPlan(uint256 planId) external;

    /// @notice Adds a DEX router to the whitelist
    /// @param dex The address of the DEX router to whitelist
    function whitelistDex(address dex) external;

    /// @notice Removes a DEX router from the whitelist
    /// @param dex The address of the DEX router to remove
    function unwhitelistDex(address dex) external;

    // View functions
    /// @notice Retrieves the details of a DCA plan
    /// @param planId The unique identifier of the plan
    /// @return The plan details
    function plans(uint256 planId) external view returns (Plan memory);

    /// @notice Checks if a DEX router is whitelisted
    /// @param dex The address of the DEX router to check
    /// @return Whether the DEX router is whitelisted
    function dexWhitelist(address dex) external view returns (bool);

    /// @notice Gets the next available plan ID
    /// @return The next plan ID
    function nextPlanId() external view returns (uint256);
} 