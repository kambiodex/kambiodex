# Alterações no periphery do Uniswap v3

> **Atualização (branch `rename-kambiodex`, out/2026):** o código do Uniswap v3 agora está **copiado** em `contratos/src/core` e
> `contratos/src/periphery` (os submódulos `v3-core`/`v3-periphery` foram removidos) e os identificadores foram renomeados
> (`UniswapV3Pool` -> `KambiodexPool`, callbacks `kambiodex*Callback`, imports `@kambiodex/...`), sem mudar a lógica.
> O `POOL_INIT_CODE_HASH` **deixou de ser igual ao oficial**: agora é `0xefa1523a…ac17`. Lista vigente: `CHANGES.md` e `NOTICE.md`.
> O texto abaixo é o histórico da decisão de 06/10/2026; onde disser "inalterado" ou "hash idêntico", vale a nota acima.

Base: `Uniswap/v3-periphery` tag **v1.1.1** (submódulo `contratos/lib/v3-periphery`, **não alterado**).
Decisão do dono em 06/10/2026: alterar o mínimo, só dois pontos. **O v3-core não foi alterado.**

> **Estado atual (18/10/2026, branch `mainnet-prep`):** só **um** arquivo do periphery está modificado:
> `NonfungiblePositionManager`. O `NonfungibleTokenPositionDescriptor` modificado foi retirado e substituído pelo
> `KambiodexPositionDescriptor`, escrito do zero (ver "Atualização" no fim). Lista oficial de mudanças em inglês: `../CHANGES.md`.
> Este documento guarda o histórico de 06/10/2026; o ponto 2 abaixo está **obsoleto**.

## Resumo

| # | Onde | Antes | Depois | Situação |
|---|------|-------|--------|----------|
| 1 | `NonfungiblePositionManager` (construtor) | nome `Uniswap V3 Positions NFT-V1`, símbolo `UNI-V3-POS` | nome `KAMBIODEX V3 Positions`, símbolo `KBX-V3-POS` | **vigente** |
| 2 | `NonfungibleTokenPositionDescriptor` (2 trechos) | `'ETH'` para o token embrulhado (WPOL) | `'POL'` | **obsoleto** (arquivo retirado; o novo descriptor mostra POL) |

Além disso, no `NonfungiblePositionManager` só mudou o que é obrigatório para compilar fora da pasta original:
- os `import './...'` viraram `import '@uniswap/v3-periphery/contracts/...'` (mesmos arquivos, mesmo conteúdo);
- um aviso de modificação no topo (4 linhas de comentário), como a GPL pede. **A licença `GPL-2.0-or-later` foi mantida**
  no `SPDX-License-Identifier`.

Nenhuma lógica de pool, preço, taxa ou dinheiro foi tocada. A cópia alterada fica em `contratos/src/periphery/`
(o `deploy` e os testes usam essa cópia; o original continua em `lib/` só como referência/dependência).

## O que NÃO mudou (de propósito)
- A lógica do v3-core inteiro (depois só houve renomeação de identificadores; o `POOL_INIT_CODE_HASH` passou a ser diferente do oficial, ver nota no topo).
- O rótulo `POL` é específico da Polygon. Na fase 2 (BNB Chain) o rótulo deve ser `BNB`: o `KambiodexPositionDescriptor`
  recebe o rótulo no construtor (`nativeLabel`), então basta publicar outro com `BNB`.

## Como conferir
```
cd contratos
diff -u lib/v3-periphery/contracts/NonfungiblePositionManager.sol src/periphery/NonfungiblePositionManager.sol
git -C lib/v3-core status --short          # vazio = núcleo intacto
git -C lib/v3-periphery status --short     # vazio = original intacto
forge test                                 # inclui os testes do nome do NFT e do descriptor
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

### 2) NonfungibleTokenPositionDescriptor.sol (OBSOLETO — arquivo retirado em 18/10/2026)
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

---

## Atualização (branch `mainnet-prep`, 18/10/2026)

- `NonfungibleTokenPositionDescriptor` (cópia alterada do Uniswap) **saiu do código**. No lugar entrou o
  `contratos/src/periphery/KambiodexPositionDescriptor.sol`, **escrito do zero**: nome do NFT no formato
  `KAMBIODEX V3 Position - 0.3% - USDC/POL - FULL RANGE`, descrição e SVG sem a palavra "Uniswap", WPOL mostrado como POL,
  símbolos de token filtrados (sem injeção de JSON/SVG) e sem revert para tokens sem `symbol()`.
- A biblioteca `NFTDescriptor` (UNLICENSED) **não é mais publicada**. A interface `IERC20Metadata` UNLICENSED foi trocada por
  `contratos/src/interfaces/IERC20Metadata.sol` (MIT, escrita do zero).
- Os contratos já publicados na Amoy continuam com o descriptor antigo (não foram tocados).
- `NonfungiblePositionManager` (mudança só de nome/símbolo) e a lógica do v3-core: **inalterados** (histórico; a renomeação posterior mudou o `POOL_INIT_CODE_HASH`, ver nota no topo).

### Nota (22/10/2026): metadado do NFT

O metadado do NFT que antes citava a marca do projeto original (no nome e na descrição, vindo da biblioteca `NFTDescriptor`)
foi substituído pelo `KambiodexPositionDescriptor`, próprio da KAMBIODEX. Os textos gerados não trazem essa marca.
Posições de faixa completa (menor ao maior tick utilizável da taxa) mostram `FULL RANGE` no nome e na imagem
(commit `cb3cf9e`). O deploy de teste com esse descriptor e um Manager novo na Amoy está em
`deployments/amoy-descriptor-v2.json`; o `amoy.json` e o `amoy-descriptor.json` seguem como registro dos deploys anteriores.
