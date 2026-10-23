# NOTICE — third-party code and licences

## Origin

KAMBIODEX is derived from **Uniswap v3** (v3-core v1.0.0 and v3-periphery v1.1.1, (c) 2021 Uniswap Labs,
<https://github.com/Uniswap/v3-core>, <https://github.com/Uniswap/v3-periphery>). The original licence headers and
copyright notices are kept in every file, and the original `LICENSE` of each repository is kept in
`contratos/src/core/LICENSE` and `contratos/src/periphery/LICENSE`.

The whole deployed package is licensed under **GPL-2.0-or-later** or a compatible permissive licence (MIT).
The full GPL-2.0 text is in [LICENSE](LICENSE). The corresponding source code is this repository.

## Modifications

Listed in detail, with hashes, in [CHANGES.md](CHANGES.md):

1. **Renaming (identifiers only)**: contracts, interfaces and callback functions named `UniswapV3*` / `uniswapV3*` were
   renamed `Kambiodex*` / `kambiodex*`, and import paths changed. No logic was changed.
2. **`POOL_INIT_CODE_HASH`** in `PoolAddress.sol` updated to the hash of the renamed pool (the callback selectors changed).
3. **`NonfungiblePositionManager`**: imports, type name and the NFT name/symbol (`KAMBIODEX V3 Positions` / `KBX-V3-POS`).
4. **Own descriptor**: `KambiodexPositionDescriptor`, written from scratch, replaces the upstream
   `NonfungibleTokenPositionDescriptor` and `NFTDescriptor` (not deployed). It limits how much of a token's `symbol()`
   it reads (64 bytes), see "Descriptor hardening" in [CHANGES.md](CHANGES.md).
5. Wrapper files `Core.sol` and `Periphery.sol` and the minimal `IERC20Metadata` interface (own code).

## Trademarks and non-affiliation

"Uniswap" and the Uniswap logo are trademarks of Uniswap Labs. KAMBIODEX is **not affiliated with, endorsed by or
sponsored by Uniswap Labs or the Uniswap Foundation**. The name is used only to state where the code comes from.
The upstream licences grant no rights over Uniswap trademarks or logos.

Licence identifiers below are the `SPDX-License-Identifier` headers found in the source files. The scope is the
88 Solidity files that make up the mainnet contracts (computed from the real import graph of `contratos/src/`).

| Folder | Source | Licence | Files deployed | Notes |
|---|---|---|---|---|
| `contratos/src/Core.sol`, `Periphery.sol`, `periphery/KambiodexPositionDescriptor.sol` | KAMBIODEX | GPL-2.0-or-later | 3 | New files; import-only wrappers and a descriptor written from scratch |
| `contratos/src/periphery/NonfungiblePositionManager.sol` | Uniswap v3-periphery v1.1.1, modified | GPL-2.0-or-later | 1 | Header kept, modification notice added |
| `contratos/src/interfaces/IERC20Metadata.sol` | KAMBIODEX | MIT | 0 (not imported by deployed contracts) | Written from scratch; replaces the UNLICENSED interface of the periphery |
| `contratos/src/core/` (from v3-core v1.0.0, `e3589b1`) | Uniswap Labs, (c) 2021 | BUSL-1.1 (10 files), GPL-2.0-or-later (22), MIT (1: `FullMath.sol`) | 33 | Identifiers renamed only; headers kept; see note on BUSL-1.1 below |
| `contratos/src/periphery/` (from v3-periphery v1.1.1, `8943ee4`) | Uniswap Labs | GPL-2.0-or-later | 35 | Identifiers/imports renamed only (+ `POOL_INIT_CODE_HASH` in `PoolAddress.sol`); headers kept |
| `contratos/lib/openzeppelin-contracts` (v3.4.1-solc-0.7-2, `1c3d6c9`) | zOS Global Limited, (c) 2016-2020 | MIT | 15 | Unmodified |
| `contratos/lib/base64` (`e78d9fd`) | Brecht Devos, (c) 2021 | MIT | 1 | Unmodified |
| `solidity-lib`, `v2-core` | Uniswap | GPL-3.0 | **not included** | Not imported by any deployed contract; submodules removed |
| `contratos/lib/forge-std` (v1.17.0) | Foundry | MIT / Apache-2.0 | not deployed | Tests and scripts only |
| `registro/` (`TokenRegistry`) | KAMBIODEX | MIT | separate deployment | Independent contract, not part of the Uniswap-derived package |
| `contratos/src/testnet/` | KAMBIODEX | GPL-2.0-or-later | not deployed | Testnet-only wrapped-native token |

## About BUSL-1.1 in Uniswap v3-core

The ten v3-core files with `SPDX-License-Identifier: BUSL-1.1` are `KambiodexFactory`, `KambiodexPool`,
`KambiodexPoolDeployer` (upstream `UniswapV3Factory`, `UniswapV3Pool`, `UniswapV3PoolDeployer`), `NoDelegateCall`, `libraries/Oracle`, `Position`, `SqrtPriceMath`, `SwapMath`, `Tick` and
`TickBitmap`. The `LICENSE` of v3-core (kept in `contratos/src/core/LICENSE`) sets:

- Licensed Work: Uniswap V3 Core, (c) 2021 Uniswap Labs
- Change Date: the earlier of 2023-04-01 or a date set at `v3-core-license-date.uniswap.eth`
- Change License: GNU General Public License v2.0 or later

The Change Date (2023-04-01 at the latest) has passed, so these files are available under **GPL-2.0-or-later**.
Their original headers are kept unchanged on purpose.

## Not part of the deployed package

The Uniswap `NFTDescriptor` library and the periphery `IERC20Metadata` interface (both `UNLICENSED` upstream) are not
imported by any deployed contract and were not copied into this repository.
