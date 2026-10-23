# CHANGES — differences from upstream Uniswap v3

KAMBIODEX is derived from Uniswap v3 and is **not affiliated with Uniswap Labs** (see [NOTICE.md](NOTICE.md)).

Baselines (upstream, copied into this repository; the git submodules were removed):

- Uniswap/v3-core **v1.0.0** — commit `e3589b192d0be27e100cd0daaf6c97204fdb1899`
- Uniswap/v3-periphery **v1.1.1** — commit `8943ee4047ea7892685802e4baf5f913993844fa`

Only the files reachable from the deployed contracts were copied (33 from core, 35 from periphery), each with its
original licence header and copyright notice untouched, plus the original `LICENSE` of each repository
(`contratos/src/core/LICENSE`, `contratos/src/periphery/LICENSE`).

## Modification 1 — renaming (identifiers only)

Pangolin-style rename so that no deployed contract name contains "Uniswap". **No logic was changed.**

| Upstream | KAMBIODEX |
|---|---|
| `UniswapV3Factory` / `UniswapV3Pool` / `UniswapV3PoolDeployer` | `KambiodexFactory` / `KambiodexPool` / `KambiodexPoolDeployer` |
| `IUniswapV3Factory`, `IUniswapV3Pool`, `IUniswapV3PoolDeployer` | `IKambiodexFactory`, `IKambiodexPool`, `IKambiodexPoolDeployer` |
| `IUniswapV3Pool{Actions,Events,State,Immutables,DerivedState,OwnerActions}` | `IKambiodexPool{Actions,Events,State,Immutables,DerivedState,OwnerActions}` |
| `IUniswapV3{Swap,Mint,Flash}Callback` | `IKambiodex{Swap,Mint,Flash}Callback` |
| `uniswapV3SwapCallback` / `uniswapV3MintCallback` / `uniswapV3FlashCallback` | `kambiodexSwapCallback` / `kambiodexMintCallback` / `kambiodexFlashCallback` |
| imports `@uniswap/v3-core/contracts/…`, `@uniswap/v3-periphery/contracts/…` | `@kambiodex/core/…`, `@kambiodex/periphery/…` |

Names without "Uniswap" (`NonfungiblePositionManager`, `SwapRouter`, `QuoterV2`, `TickLens`, libraries) are unchanged.

Proof: each of the 68 copied files, with the names above mapped back, was compared with the upstream file.
**67 are identical; the only difference is the `POOL_INIT_CODE_HASH` line of Modification 2.**

## Modification 2 — `POOL_INIT_CODE_HASH`

`contratos/src/periphery/libraries/PoolAddress.sol`:

- upstream: `0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54`
- KAMBIODEX: `0xefa1523a9c693954cc7417070043ba156e89adf78e52919814d859ef413bac17`

The pool bytecode changed only because the callback function names (and therefore their 4-byte selectors) changed.
The compiler settings are the same as upstream (solc 0.7.6, optimizer runs 800, `bytecode_hash = none`).
Consequence: pool addresses differ from the official Uniswap v3 ones, and third-party routers that implement
`uniswapV3SwapCallback` do not work with KAMBIODEX pools.

## Modification 3 — `NonfungiblePositionManager`

`contratos/src/periphery/NonfungiblePositionManager.sol`, from `contracts/NonfungiblePositionManager.sol` (v1.1.1).

- Licence header kept (`GPL-2.0-or-later`); a modification notice added after it.
- Relative imports rewritten as `@kambiodex/core/…` / `@kambiodex/periphery/…` (same files, same content).
- Type `IUniswapV3Pool` renamed `IKambiodexPool` (Modification 1).
- NFT name/symbol: `'Uniswap V3 Positions NFT-V1'` / `'UNI-V3-POS'` → `'KAMBIODEX V3 Positions'` / `'KBX-V3-POS'`.

```
SHA-256 upstream  d66525ca236d3495779c247c4b4417657181c2932c9af126a086444e3142a64b
SHA-256 modified  08a2a7c18006731e707c2f18719094c37ff1557e420bc9e8229d6aec783d32ff
```

## New files (written by KAMBIODEX, not copied from upstream)

| File | Licence | SHA-256 | Purpose |
|---|---|---|---|
| `contratos/src/Core.sol` | GPL-2.0-or-later | `99f2b0422c98607526ed5dd3809a62447020f25cb13da88185413dc4e38796b4` | Imports `KambiodexFactory` and `KambiodexPool` so they compile from this project |
| `contratos/src/Periphery.sol` | GPL-2.0-or-later | `df129dc70e09fea24ab164b30c12790c262fc5884d435d73f40e4e6ce6e41950` | Imports `SwapRouter` and `QuoterV2` |
| `contratos/src/periphery/KambiodexPositionDescriptor.sol` | GPL-2.0-or-later | `8c1273b1aa6c3eddd8b375f5876b9bedb7f8784135983bf36c41b48ed4b14c91` | `tokenURI` generator for position NFTs (own code, own texts); replaces upstream `NonfungibleTokenPositionDescriptor` and `NFTDescriptor` |
| `contratos/src/interfaces/IERC20Metadata.sol` | MIT | `d2c7022a475698fede1301937e061a9ece3f7a06f5f97e53c26503eebed335a8` | Minimal `name/symbol/decimals` interface; replaces the UNLICENSED upstream one |

`KambiodexPositionDescriptor` implements the unchanged upstream interface `INonfungibleTokenPositionDescriptor`.
The `NonfungiblePositionManager` stores the descriptor address as `immutable`, chosen at deployment.

## Not used in the deployment

Upstream `NonfungibleTokenPositionDescriptor`, `libraries/NFTDescriptor`, `interfaces/IERC20Metadata` (UNLICENSED),
`V3Migrator`, `UniswapInterfaceMulticall`, and all upstream `test/` contracts were not copied.

## Other (not part of the Uniswap-derived contracts)

- `registro/src/TokenRegistry.sol` — MIT, separate contract.
- `contratos/src/testnet/WrappedNativeTestnet.sol` — testnet only.
- Tests, scripts and deploy helpers in `contratos/test`, `contratos/script`.
