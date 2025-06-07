// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {P256ValidationModule} from "../../src/modules/P256ValidationModule.sol";
import {DCAModule} from "../../src/modules/DCAModule.sol";
import {P256PublicKey} from "../../src/utils/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SigningUtilsLib} from "../helpers/SigningUtilsLib.sol";
import {FCL_ecdsa_utils} from "@FCL/FCL_ecdsa_utils.sol";
import {console} from "forge-std/console.sol";

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

contract P256AccountTest is Test {
    P256ValidationModule public validationModule;
    DCAModule public dcaModule;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockDEXRouter public dexRouter;
    address public account;
    uint256 public privateKey;
    P256PublicKey public passkey;
    uint32 public constant ENTITY_ID = 1;
    bytes4 public constant _1271_MAGIC_VALUE = 0x1626ba7e;

    function setUp() public {
        // Deploy modules
        validationModule = new P256ValidationModule();
        dcaModule = new DCAModule();

        // Deploy tokens and DEX
        tokenIn = new MockERC20("Token In", "TIN");
        tokenOut = new MockERC20("Token Out", "TOUT");
        dexRouter = new MockDEXRouter();

        // Create test account and generate P-256 key pair
        (account, privateKey) = makeAddrAndKey("testAccount");
        (uint256 x, uint256 y) = FCL_ecdsa_utils.ecdsa_derivKpub(privateKey);
        passkey = P256PublicKey({x: x, y: y});

        // Whitelist DEX
        dcaModule.whitelistDex(address(dexRouter));

        // Mint tokens to account
        tokenIn.mint(account, 1000 ether);
    }

    function test_InstallModules() public {
        vm.startPrank(account);

        // Install P256ValidationModule
        bytes memory installData = abi.encode(ENTITY_ID, passkey);
        validationModule.onInstall(installData);

        // Verify passkey was installed
        (uint256 x, uint256 y) = validationModule.passkeys(ENTITY_ID, account);
        assertEq(x, passkey.x);
        assertEq(y, passkey.y);

        // Install DCAModule
        dcaModule.onInstall("");

        vm.stopPrank();
    }

    function test_CreateAndExecuteDCAPlan() public {
        vm.startPrank(account);

        // Install modules
        bytes memory installData = abi.encode(ENTITY_ID, passkey);
        validationModule.onInstall(installData);
        dcaModule.onInstall("");

        // Create DCA plan
        uint256 amount = 100 ether;
        uint256 interval = 1 days;
        uint256 planId = dcaModule.createPlan(address(tokenIn), address(tokenOut), amount, interval);

        // Approve tokens for DCA module
        tokenIn.approve(address(dcaModule), amount);

        // Fast forward time
        vm.warp(block.timestamp + interval);

        // Create and sign user operation
        bytes memory swapData = abi.encodeWithSelector(MockDEXRouter.swap.selector, "");
        bytes32 userOpHash = keccak256(abi.encode(
            account, // sender
            0, // nonce
            "", // initCode
            abi.encodeWithSelector(dcaModule.executePlan.selector, planId, address(dexRouter), swapData), // callData
            bytes32(0), // accountGasLimits
            0, // preVerificationGas
            bytes32(0), // gasFees
            "", // paymasterAndData
            "" // signature (will be set after signing)
        ));

        bytes memory signature = SigningUtilsLib.signHashP256(privateKey, userOpHash);

        // Validate signature
        bytes4 result = validationModule.validateSignature(
            account,
            ENTITY_ID,
            address(0),
            userOpHash,
            signature
        );
        assertEq(result, _1271_MAGIC_VALUE);

        // Execute DCA plan
        dcaModule.executePlan(planId, address(dexRouter), swapData);

        vm.stopPrank();
    }

    function test_UninstallModules() public {
        vm.startPrank(account);

        // Install modules first
        bytes memory installData = abi.encode(ENTITY_ID, passkey);
        validationModule.onInstall(installData);
        dcaModule.onInstall("");

        // Uninstall P256ValidationModule
        bytes memory uninstallData = abi.encode(ENTITY_ID);
        validationModule.onUninstall(uninstallData);

        // Verify passkey was removed
        (uint256 x, uint256 y) = validationModule.passkeys(ENTITY_ID, account);
        assertEq(x, 0);
        assertEq(y, 0);

        // Uninstall DCAModule
        dcaModule.onUninstall("");

        vm.stopPrank();
    }
}
