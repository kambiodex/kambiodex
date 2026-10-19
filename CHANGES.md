# CHANGES — differences from upstream Uniswap v3

Baselines (git submodules, unmodified, `git status` clean inside each):

- Uniswap/v3-core **v1.0.0** — commit `e3589b192d0be27e100cd0daaf6c97204fdb1899`
- Uniswap/v3-periphery **v1.1.1** — commit `8943ee4047ea7892685802e4baf5f913993844fa`

## v3-core

**No file modified.** The `UniswapV3Pool` bytecode and `POOL_INIT_CODE_HASH` are identical to the official ones
(same solc 0.7.6, optimizer runs 800, `bytecode_hash = none`; see `contratos/foundry.toml`).

## v3-periphery

### Modified (1 file)

`contratos/src/periphery/NonfungiblePositionManager.sol`, from `contracts/NonfungiblePositionManager.sol` (v1.1.1).

- Licence header kept (`GPL-2.0-or-later`); a 4-line modification notice added after it.
- Relative imports (`./interfaces/...`, `./libraries/...`, `./base/...`) rewritten as `@uniswap/v3-periphery/contracts/...`
  (same files, same content).
- NFT name/symbol: `'Uniswap V3 Positions NFT-V1'` / `'UNI-V3-POS'` → `'KAMBIODEX V3 Positions'` / `'KBX-V3-POS'`.

Real diff: 28 changed lines (`diff` of the two files). Reproduce with:

```
cd contratos
diff -u lib/v3-periphery/contracts/NonfungiblePositionManager.sol src/periphery/NonfungiblePositionManager.sol
```

```
SHA-256 upstream  d66525ca236d3495779c247c4b4417657181c2932c9af126a086444e3142a64b
SHA-256 modified  e30d84739775512a999246570ce24b17bb5b00751c4258b22b3bce3b046aac8e
```

## New files (written by KAMBIODEX, not copied from upstream)

| File | Licence | SHA-256 | Purpose |
|---|---|---|---|
| `contratos/src/Core.sol` | GPL-2.0-or-later | `d8ace52ae2a721ed7e19af75ea89f697ce89098af7a4501cad240febfe0962e1` | Imports `UniswapV3Factory` and `UniswapV3Pool` so they compile from this project |
| `contratos/src/Periphery.sol` | GPL-2.0-or-later | `b306df10faf8e597516e8819cf61d262023e19f92ec4d05c86755c31a6535dc1` | Imports `SwapRouter` and `QuoterV2` |
| `contratos/src/periphery/KambiodexPositionDescriptor.sol` | GPL-2.0-or-later | `2c1d2964f63c22d3ff8f1feabb440f66ae06294cb8e27475209c35b71fd029f8` | `tokenURI` generator for position NFTs; replaces upstream `NonfungibleTokenPositionDescriptor` and `NFTDescriptor` |
| `contratos/src/interfaces/IERC20Metadata.sol` | MIT | `d2c7022a475698fede1301937e061a9ece3f7a06f5f97e53c26503eebed335a8` | Minimal `name/symbol/decimals` interface; replaces the UNLICENSED upstream one |

`KambiodexPositionDescriptor` implements the unchanged upstream interface `INonfungibleTokenPositionDescriptor`.
The `NonfungiblePositionManager` stores the descriptor address as `immutable`, chosen at deployment.

## Not used in the deployment

Upstream `NonfungibleTokenPositionDescriptor`, `libraries/NFTDescriptor` and `interfaces/IERC20Metadata` (UNLICENSED)
are not compiled into any deployed contract.

## Other (not part of the Uniswap-derived contracts)

- `registro/src/TokenRegistry.sol` — MIT, separate contract.
- `contratos/src/testnet/WrappedNativeTestnet.sol` — testnet only.
- Tests, scripts and deploy helpers in `contratos/test`, `contratos/script`.
