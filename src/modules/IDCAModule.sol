// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6900ExecutionModule} from "@erc6900/reference-implementation/interfaces/IERC6900ExecutionModule.sol";

interface IDCAModule is IERC165, IERC6900ExecutionModule {
    // Events
    event PlanCreated(uint256 indexed id, address tokenIn, address tokenOut);
    event PlanExecuted(uint256 indexed id);
    event PlanCancelled(uint256 indexed id);
    event DexWhitelisted(address indexed dex);
    event DexUnwhitelisted(address indexed dex);

    // Errors
    error PlanNotFound();
    error PlanInactive();
    error DexNotWhitelisted();
    error TooEarly();
    error InvalidAmount();
    error InvalidInterval();

    // Structs
    struct Plan {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint256 interval;
        uint256 lastExecution;
        bool active;
    }

    // Functions
    function createPlan(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 interval
    ) external returns (uint256 planId);

    function executePlan(
        uint256 planId,
        address dex,
        bytes calldata swapData
    ) external;

    function cancelPlan(uint256 planId) external;

    function whitelistDex(address dex) external;

    function unwhitelistDex(address dex) external;

    // View functions
    function plans(uint256 planId) external view returns (Plan memory);

    function dexWhitelist(address dex) external view returns (bool);

    function nextPlanId() external view returns (uint256);
} 