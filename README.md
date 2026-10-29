# KAMBIODEX contracts

KAMBIODEX is a decentralized exchange (DEX) with concentrated liquidity, live on Polygon PoS (chain ID 137).
The contracts are derived from **Uniswap v3** (core v1.0.0, periphery v1.1.1, (c) Uniswap Labs), with minimal, documented
changes. KAMBIODEX is **not affiliated with Uniswap Labs**; "Uniswap" is a trademark of its owner and is used here only to
credit the origin of the code. Licence and copyright notices of the original files are kept (see [NOTICE.md](NOTICE.md)).

- Pool logic and fees are the same as upstream. The only change in core is **renaming** (`UniswapV3Pool` -> `KambiodexPool`,
  callbacks `uniswapV3*Callback` -> `kambiodex*Callback`, etc.); no logic was changed. Because of the renamed callbacks,
  `POOL_INIT_CODE_HASH` differs from the official one: `0xefa1523a9c693954cc7417070043ba156e89adf78e52919814d859ef413bac17`.
- The upstream code is copied into `contratos/src/core` and `contratos/src/periphery` (no submodules for it).
- `NonfungiblePositionManager` also has the NFT name/symbol changed. See [CHANGES.md](CHANGES.md).
- The position-NFT descriptor is a new contract written from scratch (`KambiodexPositionDescriptor`).
- No proxy, no upgrade. The factory owner can set the protocol fee share, collect it and enable fee tiers;
  it cannot move users' liquidity.

## Layout

```
contratos/        Foundry project (src/core + src/periphery = Uniswap v3 derived, test/, script/, lib/ = OpenZeppelin, base64, forge-std)
registro/         TokenRegistry (separate MIT contract)
deployments/      Published addresses per network (<network>.json)
```

## Build and test

```
git submodule update --init --recursive   # OpenZeppelin, base64, forge-std
cd contratos
forge build
forge test
```

Compiler versions are pinned (0.7.6 for the Uniswap-derived contracts, 0.8.37 for tests and scripts); see
`contratos/foundry.toml`.

## Licence

- Deployed package: **GPL-2.0-or-later**, with MIT dependencies. Full text in [LICENSE](LICENSE).
- Files derived from Uniswap v3-core carry `BUSL-1.1` headers (kept as in the original); that licence converted to GPL-2.0-or-later on its Change Date
  (2023-04-01 at the latest).
- Per-folder details and third-party copyrights: [NOTICE.md](NOTICE.md).
- Differences from upstream: [CHANGES.md](CHANGES.md).

## Status

Live on Polygon PoS mainnet (chain ID 137). Official addresses are in [deployments/polygon.json](deployments/polygon.json); earlier test deployments on Polygon Amoy are kept in the same folder.

The upstream Uniswap v3 code was publicly audited. The KAMBIODEX changes have not had a separate third-party audit yet; our security plan is in [seguranca/](seguranca/). Use at your own risk.
