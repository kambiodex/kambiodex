# NOTICE — third-party code and licences

KAMBIODEX deploys the Uniswap v3 contracts (core v1.0.0, periphery v1.1.1) with the minimal changes listed in
[CHANGES.md](CHANGES.md). The whole deployed package is licensed under **GPL-2.0-or-later** or a compatible
permissive licence (MIT). The full GPL-2.0 text is in [LICENSE](LICENSE).

Licence identifiers below are the `SPDX-License-Identifier` headers found in the source files. The scope is the
88 Solidity files that make up the mainnet contracts (computed from the real import graph of `contratos/src/`).

| Folder | Source | Licence | Files deployed | Notes |
|---|---|---|---|---|
| `contratos/src/Core.sol`, `Periphery.sol`, `periphery/KambiodexPositionDescriptor.sol` | KAMBIODEX | GPL-2.0-or-later | 3 | New files; import-only wrappers and a descriptor written from scratch |
| `contratos/src/periphery/NonfungiblePositionManager.sol` | Uniswap v3-periphery v1.1.1, modified | GPL-2.0-or-later | 1 | Header kept, modification notice added |
| `contratos/src/interfaces/IERC20Metadata.sol` | KAMBIODEX | MIT | 0 (not imported by deployed contracts) | Written from scratch; replaces the UNLICENSED interface of the periphery |
| `contratos/lib/v3-core` (v1.0.0, `e3589b1`) | Uniswap Labs, (c) 2021 | BUSL-1.1 (10 files), GPL-2.0-or-later (22), MIT (1: `FullMath.sol`) | 33 | See note on BUSL-1.1 below |
| `contratos/lib/v3-periphery` (v1.1.1, `8943ee4`) | Uniswap Labs | GPL-2.0-or-later | 35 | Unmodified |
| `contratos/lib/openzeppelin-contracts` (v3.4.1-solc-0.7-2, `1c3d6c9`) | zOS Global Limited, (c) 2016-2020 | MIT | 15 | Unmodified |
| `contratos/lib/base64` (`e78d9fd`) | Brecht Devos, (c) 2021 | MIT | 1 | Unmodified |
| `contratos/lib/solidity-lib` (`c01640b`) | Uniswap | GPL-3.0 | **not included** | Not imported by any deployed contract |
| `contratos/lib/v2-core` (`4dd5906`) | Uniswap | GPL-3.0 | **not included** | Not imported by any deployed contract |
| `contratos/lib/forge-std` (v1.17.0) | Foundry | MIT / Apache-2.0 | not deployed | Tests and scripts only |
| `registro/` (`TokenRegistry`) | KAMBIODEX | MIT | separate deployment | Independent contract, not part of the Uniswap-derived package |
| `contratos/src/testnet/` | KAMBIODEX | GPL-2.0-or-later | not deployed | Testnet-only wrapped-native token |

## About BUSL-1.1 in Uniswap v3-core

The ten v3-core files with `SPDX-License-Identifier: BUSL-1.1` are `UniswapV3Factory`, `UniswapV3Pool`,
`UniswapV3PoolDeployer`, `NoDelegateCall`, `libraries/Oracle`, `Position`, `SqrtPriceMath`, `SwapMath`, `Tick` and
`TickBitmap`. The `LICENSE` of `lib/v3-core` sets:

- Licensed Work: Uniswap V3 Core, (c) 2021 Uniswap Labs
- Change Date: the earlier of 2023-04-01 or a date set at `v3-core-license-date.uniswap.eth`
- Change License: GNU General Public License v2.0 or later

The Change Date (2023-04-01 at the latest) has passed, so these files are available under **GPL-2.0-or-later**.
Their original headers are kept unchanged on purpose.

## Not part of the deployed package

The Uniswap `NFTDescriptor` library and the periphery `IERC20Metadata` interface (both `UNLICENSED` upstream) are not
imported by any deployed contract; they remain only inside the `lib/v3-periphery` submodule as upstream reference.
