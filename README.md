# P256 Smart Wallet

A modular smart wallet implementation that uses P256 (secp256r1) signatures for WebAuthn compatibility. This project implements ERC-6900 (Modular Account) standard with P256 validation and DCA (Dollar Cost Averaging) execution modules.

## Features

- **P256 Validation**: WebAuthn-compatible signature validation using the P256 elliptic curve
- **Modular Architecture**: Implements ERC-6900 for modular account functionality
- **DCA Module**: Automated token swaps through whitelisted DEX routers
- **Factory Pattern**: Deterministic account creation with CREATE2
- **Gas Optimized**: Uses RIP-7212 precompile when available

## Architecture

The project consists of several key components:

### Core Modules

- **P256ValidationModule**: Handles signature validation using P256 curve
- **DCAModule**: Manages recurring token swap plans
- **P256AccountFactory**: Creates and initializes modular accounts

### Libraries

- **P256VerifierLib**: Core P256 signature verification
- **P256SCLVerifierLib**: SCL-optimized P256 verification with RIP-7212 support

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for development)
- Git

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/p256-smart-wallet.git
cd p256-smart-wallet
```

2. Install dependencies:
```bash
forge install
```

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

### Local Development

Start a local Anvil instance:
```bash
anvil
```

## Deployment

1. Set up your environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

2. Deploy the contracts:
```bash
forge script script/P256Account.s.sol:P256AccountScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Usage

### Creating a New Account

```solidity
// Deploy a new account with P256 validation
P256AccountFactory factory = new P256AccountFactory(
    entryPoint,
    accountImpl,
    p256ValidationModule,
    factoryOwner
);

// Create a new account
P256PublicKey memory key = P256PublicKey({
    x: xCoordinate,
    y: yCoordinate
});
ReferenceModularAccount account = factory.createAccount(salt, entityId, key);
```

### Creating a DCA Plan

```solidity
// Create a new DCA plan
uint256 planId = dcaModule.createPlan(
    tokenIn,
    tokenOut,
    amount,
    interval
);

// Execute the plan
dcaModule.executePlan(
    planId,
    dexRouter,
    swapData
);
```

## Security

- All contracts are thoroughly tested
- Re-entrancy protection implemented
- DEX router whitelisting
- Signature validation using P256 curve
- Gas optimizations with RIP-7212 precompile

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [ERC-6900](https://eips.ethereum.org/EIPS/eip-6900) for the modular account standard
- [RIP-7212](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md) for P256 precompile
- [Metamask delegation framework](https://github.com/MetaMask/delegation-framework) for test utils
- [Foundry](https://book.getfoundry.sh/) for the development framework
