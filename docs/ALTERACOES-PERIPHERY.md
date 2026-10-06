# Alterações no periphery do Uniswap v3

Base: `Uniswap/v3-periphery` tag **v1.1.1** (submódulo `contratos/lib/v3-periphery`, **não alterado**).
Decisão do dono em 06/10/2026: alterar o mínimo, só dois pontos. **O v3-core não foi alterado.**

## Resumo

| # | Onde | Antes | Depois |
|---|------|-------|--------|
| 1 | `NonfungiblePositionManager` (construtor) | nome `Uniswap V3 Positions NFT-V1`, símbolo `UNI-V3-POS` | nome `KAMBIODEX V3 Positions`, símbolo `KBX-V3-POS` |
| 2 | `NonfungibleTokenPositionDescriptor` (2 trechos) | `'ETH'` para o token embrulhado (WPOL) | `'POL'` |

Além dos dois pontos, só mudou o que é obrigatório para compilar fora da pasta original:
- os `import './...'` viraram `import '@uniswap/v3-periphery/contracts/...'` (mesmos arquivos, mesmo conteúdo);
- um aviso de modificação no topo (3 linhas de comentário), como a GPL pede. **A licença `GPL-2.0-or-later` foi mantida**
  no `SPDX-License-Identifier` dos dois arquivos.

Nenhuma lógica de pool, preço, taxa ou dinheiro foi tocada. As cópias alteradas ficam em `contratos/src/periphery/`
(o `deploy` e os testes usam essas cópias; os originais continuam em `lib/` só como referência/dependência).

## O que NÃO mudou (de propósito)
- `libraries/NFTDescriptor.sol` (biblioteca, UNLICENSED) continua escrevendo **"Uniswap"** no metadado do NFT:
  linha 115 `'This NFT represents a liquidity position in a Uniswap V3 '` e linha 163 `'Uniswap - '`. Ver `duvidas-para-advogado.md`, ponto 4.
- O rótulo `POL` é específico da Polygon. Na fase 2 (BNB Chain) o rótulo deveria ser `BNB`: será preciso outra cópia/parametrização.
- `POOL_INIT_CODE_HASH` e todo o v3-core continuam idênticos ao oficial (conferido em 06/10/2026).

## Como conferir
```
cd contratos
diff -u lib/v3-periphery/contracts/NonfungiblePositionManager.sol src/periphery/NonfungiblePositionManager.sol
diff -u lib/v3-periphery/contracts/NonfungibleTokenPositionDescriptor.sol src/periphery/NonfungibleTokenPositionDescriptor.sol
git -C lib/v3-core status --short          # vazio = núcleo intacto
git -C lib/v3-periphery status --short     # vazio = original intacto
forge test                                 # inclui os testes do nome e do rótulo POL
```

## Diff exato

### 1) NonfungiblePositionManager.sol
```diff
--- a/contracts/NonfungiblePositionManager.sol
+++ b/src/periphery/NonfungiblePositionManager.sol
@@ -1,4 +1,8 @@
 // SPDX-License-Identifier: GPL-2.0-or-later
+// Modified by KAMBIODEX (2026-10-06) from Uniswap/v3-periphery v1.1.1, file contracts/NonfungiblePositionManager.sol.
+// Changes: (1) relative imports rewritten to @uniswap/v3-periphery/...; (2) NFT name/symbol changed.
+// Original name/symbol: 'Uniswap V3 Positions NFT-V1' / 'UNI-V3-POS'.
+// Licence unchanged (GPL-2.0-or-later). Full diff: docs/ALTERACOES-PERIPHERY.md
 pragma solidity =0.7.6;
 pragma abicoder v2;
 
@@ -6,17 +10,17 @@
 import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
 import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
 
-import './interfaces/INonfungiblePositionManager.sol';
-import './interfaces/INonfungibleTokenPositionDescriptor.sol';
-import './libraries/PositionKey.sol';
-import './libraries/PoolAddress.sol';
-import './base/LiquidityManagement.sol';
-import './base/PeripheryImmutableState.sol';
-import './base/Multicall.sol';
-import './base/ERC721Permit.sol';
-import './base/PeripheryValidation.sol';
-import './base/SelfPermit.sol';
-import './base/PoolInitializer.sol';
+import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
+import '@uniswap/v3-periphery/contracts/interfaces/INonfungibleTokenPositionDescriptor.sol';
+import '@uniswap/v3-periphery/contracts/libraries/PositionKey.sol';
+import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
+import '@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol';
+import '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol';
+import '@uniswap/v3-periphery/contracts/base/Multicall.sol';
+import '@uniswap/v3-periphery/contracts/base/ERC721Permit.sol';
+import '@uniswap/v3-periphery/contracts/base/PeripheryValidation.sol';
+import '@uniswap/v3-periphery/contracts/base/SelfPermit.sol';
+import '@uniswap/v3-periphery/contracts/base/PoolInitializer.sol';
 
 /// @title NFT positions
 /// @notice Wraps Uniswap V3 positions in the ERC721 non-fungible token interface
@@ -72,7 +76,7 @@
         address _factory,
         address _WETH9,
         address _tokenDescriptor_
-    ) ERC721Permit('Uniswap V3 Positions NFT-V1', 'UNI-V3-POS', '1') PeripheryImmutableState(_factory, _WETH9) {
+    ) ERC721Permit('KAMBIODEX V3 Positions', 'KBX-V3-POS', '1') PeripheryImmutableState(_factory, _WETH9) {
         _tokenDescriptor = _tokenDescriptor_;
     }
 
```

### 2) NonfungibleTokenPositionDescriptor.sol
```diff
--- a/contracts/NonfungibleTokenPositionDescriptor.sol
+++ b/src/periphery/NonfungibleTokenPositionDescriptor.sol
@@ -1,17 +1,20 @@
 // SPDX-License-Identifier: GPL-2.0-or-later
+// Modified by KAMBIODEX (2026-10-06) from Uniswap/v3-periphery v1.1.1, file contracts/NonfungibleTokenPositionDescriptor.sol.
+// Changes: (1) relative imports rewritten to @uniswap/v3-periphery/...; (2) wrapped-native label ETH -> POL (2 places).
+// Licence unchanged (GPL-2.0-or-later). Full diff: docs/ALTERACOES-PERIPHERY.md
 pragma solidity =0.7.6;
 pragma abicoder v2;
 
 import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
 import '@uniswap/lib/contracts/libraries/SafeERC20Namer.sol';
 
-import './libraries/ChainId.sol';
-import './interfaces/INonfungiblePositionManager.sol';
-import './interfaces/INonfungibleTokenPositionDescriptor.sol';
-import './interfaces/IERC20Metadata.sol';
-import './libraries/PoolAddress.sol';
-import './libraries/NFTDescriptor.sol';
-import './libraries/TokenRatioSortOrder.sol';
+import '@uniswap/v3-periphery/contracts/libraries/ChainId.sol';
+import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
+import '@uniswap/v3-periphery/contracts/interfaces/INonfungibleTokenPositionDescriptor.sol';
+import '@uniswap/v3-periphery/contracts/interfaces/IERC20Metadata.sol';
+import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
+import '@uniswap/v3-periphery/contracts/libraries/NFTDescriptor.sol';
+import '@uniswap/v3-periphery/contracts/libraries/TokenRatioSortOrder.sol';
 
 /// @title Describes NFT token positions
 /// @notice Produces a string containing the data URI for a JSON metadata string
@@ -58,9 +61,9 @@
                     quoteTokenAddress: quoteTokenAddress,
                     baseTokenAddress: baseTokenAddress,
                     quoteTokenSymbol: quoteTokenAddress == WETH9
-                        ? 'ETH'
+                        ? 'POL'
                         : SafeERC20Namer.tokenSymbol(quoteTokenAddress),
-                    baseTokenSymbol: baseTokenAddress == WETH9 ? 'ETH' : SafeERC20Namer.tokenSymbol(baseTokenAddress),
+                    baseTokenSymbol: baseTokenAddress == WETH9 ? 'POL' : SafeERC20Namer.tokenSymbol(baseTokenAddress),
                     quoteTokenDecimals: IERC20Metadata(quoteTokenAddress).decimals(),
                     baseTokenDecimals: IERC20Metadata(baseTokenAddress).decimals(),
                     flipRatio: _flipRatio,
```

## Impressões digitais (SHA-256)
```
d66525ca236d3495779c247c4b4417657181c2932c9af126a086444e3142a64b  lib/v3-periphery/contracts/NonfungiblePositionManager.sol
e30d84739775512a999246570ce24b17bb5b00751c4258b22b3bce3b046aac8e  src/periphery/NonfungiblePositionManager.sol
91d34c9bb608378c57cf78462b32cf275fb5ac0c7d975e2ecd58bf44412d89c5  lib/v3-periphery/contracts/NonfungibleTokenPositionDescriptor.sol
803a9b342f513d44c00c26eaa02f08e81f02cceacdc35f5c8ef87744cbe149ec  src/periphery/NonfungibleTokenPositionDescriptor.sol
```
