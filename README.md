# KAMBIODEX contracts

KAMBIODEX is a decentralized exchange (DEX) with concentrated liquidity, launching on Polygon PoS (chain ID 137).
The contracts are the original **Uniswap v3** (core v1.0.0, periphery v1.1.1) with minimal, documented changes.

- Pool logic, fees and `POOL_INIT_CODE_HASH` are identical to upstream: **v3-core is not modified**.
- Only one upstream file is modified (`NonfungiblePositionManager`: NFT name/symbol). See [CHANGES.md](CHANGES.md).
- The position-NFT descriptor is a new contract written from scratch (`KambiodexPositionDescriptor`).
- No proxy, no upgrade. The factory owner can set the protocol fee share, collect it and enable fee tiers;
  it cannot move users' liquidity.

## Layout

```
contratos/        Foundry project (src/, test/, script/, lib/ = git submodules)
registro/         TokenRegistry (separate MIT contract)
deployments/      Published addresses per network (<network>.json)
```

## Build and test

```
git submodule update --init --recursive
cd contratos
forge build
forge test
```

Compiler versions are pinned (0.7.6 for the Uniswap-derived contracts, 0.8.37 for tests and scripts); see
`contratos/foundry.toml`.

## Licence

- Deployed package: **GPL-2.0-or-later**, with MIT dependencies. Full text in [LICENSE](LICENSE).
- Uniswap v3-core files carry `BUSL-1.1` headers; that licence converted to GPL-2.0-or-later on its Change Date
  (2023-04-01 at the latest).
- Per-folder details and third-party copyrights: [NOTICE.md](NOTICE.md).
- Differences from upstream: [CHANGES.md](CHANGES.md).

## Status

Testnet stage (Polygon Amoy). Nothing is deployed to mainnet until the audit and legal review are complete.
