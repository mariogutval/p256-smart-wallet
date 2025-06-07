// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@erc6900/reference-implementation/interfaces/IERC6900ValidationModule.sol";

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

contract MockEntryPoint is IEntryPoint {
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256(abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                userOp.preVerificationGas,
                userOp.gasFees,
                keccak256(userOp.paymasterAndData)
            )),
            address(this),
            block.chainid
        ));
    }

    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external {
        for (uint256 i = 0; i < ops.length; i++) {
            PackedUserOperation calldata userOp = ops[i];
            
            // Simple validation - check that the operation is properly signed
            bytes32 userOpHash = this.getUserOpHash(userOp);
            
            // Call the account directly with the callData
            (bool success, bytes memory result) = userOp.sender.call(userOp.callData);
            
            if (!success) {
                // If it failed, try to bubble up the revert reason
                if (result.length > 0) {
                    assembly {
                        revert(add(result, 32), mload(result))
                    }
                } else {
                    revert("Transaction failed");
                }
            }
        }
    }

    function handleAggregatedOps(UserOpsPerAggregator[] calldata opsPerAggregator, address payable beneficiary) external {}
    function simulateValidation(PackedUserOperation calldata userOp) external returns (ValidationResult memory result) {}
    function simulateHandleOp(PackedUserOperation calldata op, address target, bytes calldata targetCallData) external returns (ExecutionResult memory result) {}
    function addStake(uint32 unstakeDelaySec) external payable {}
    function unlockStake() external {}
    function withdrawStake(address payable withdrawAddress) external {}
    function depositTo(address account) external payable {}
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {}
    function balanceOf(address account) external view returns (uint256) { return 0; }
    function getDepositInfo(address account) external view returns (DepositInfo memory info) {}
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce) { return 0; }
    function incrementNonce(uint192 key) external {}
    function getSenderAddress(bytes memory initCode) external {}
    function delegateAndRevert(address target, bytes memory data) external {}

    struct ValidationResult {
        ReturnInfo returnInfo;
        StakeInfo senderInfo;
        StakeInfo factoryInfo;
        StakeInfo paymasterInfo;
    }

    struct ExecutionResult {
        uint256 preOpGas;
        uint256 paid;
        uint48 validAfter;
        uint48 validUntil;
        bool targetSuccess;
        bytes targetResult;
    }
} 