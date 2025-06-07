// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Forge imports
import {Test} from "forge-std/Test.sol";

// OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// FCL imports
import {FCL_ecdsa_utils} from "@FCL/FCL_ecdsa_utils.sol";

// Local imports
import {P256PublicKey} from "../../src/utils/Types.sol";

contract BaseTest is Test {
    struct TestUser {
        string name;
        address payable addr;
        uint256 privateKey;
        uint256 x;
        uint256 y;
    }

    // Common constants
    bytes4 internal constant _1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _1271_INVALID = 0xffffffff;
    uint32 internal constant DEFAULT_ENTITY_ID = 1;

    // Common test setup
    function createUser(string memory _name) internal returns (TestUser memory user_) {
        (address addr_, uint256 privateKey_) = makeAddrAndKey(_name);
        vm.deal(addr_, 100 ether);
        vm.label(addr_, _name);

        user_.name = _name;
        user_.addr = payable(addr_);
        user_.privateKey = privateKey_;
        (user_.x, user_.y) = FCL_ecdsa_utils.ecdsa_derivKpub(user_.privateKey);
    }

    function createP256Key(uint256 privateKey) internal view returns (P256PublicKey memory) {
        (uint256 x, uint256 y) = FCL_ecdsa_utils.ecdsa_derivKpub(privateKey);
        return P256PublicKey({x: x, y: y});
    }
}

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
    bool public shouldFail;
    bool public shouldReenter;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setShouldReenter(bool _shouldReenter) external {
        shouldReenter = _shouldReenter;
    }

    function swap(bytes calldata) external view returns (bool) {
        if (shouldFail) {
            revert("DEX: swap failed");
        }
        return true;
    }
}
