# KAMBIODEX — contratos (Foundry)

Uniswap v3 original (core `v1.0.0`, periphery `v1.1.1`), sem alterar a lógica. Ver `../CLAUDE.md`.

## Alterações no periphery

Só dois arquivos foram alterados (nome/símbolo do NFT e rótulo POL), em `src/periphery/`; o resto vem de `lib/` sem alteração.
Detalhes e diff exato: `../docs/ALTERACOES-PERIPHERY.md`.

## Testes (não gastam nada, rodam só no computador)

```
cd contratos
forge test
```

- `test/Core.t.sol` — pools, faixas de taxa, posições, trocas, `collect`, `setFeeProtocol(6,6)`, `collectProtocol`.
- `test/Periphery.t.sol` — posições em NFT, remover 25/50/75/100%, SwapRouter, QuoterV2, POL nativo, desenho do NFT.
- `test/Deploy.t.sol` — o próprio script de deploy (montagem, dono, faixas, bloqueio de rede principal).

## Deploy em rede de teste (AINDA NÃO EXECUTADO)

O script `script/Deploy.s.sol` só aceita **Polygon Amoy (80002)** e **BNB Testnet (97)**.
Polygon (137) e BNB Chain (56) são bloqueadas de propósito (CLAUDE.md: nada em rede principal
antes de auditoria + liberação jurídica).

A chave privada **nunca** vai em arquivo: use uma carteira criptografada do Foundry ou uma carteira física.

1. `cp .env.example .env` e preencher `AMOY_RPC_URL` e `OWNER_ADDRESS` (só endereços públicos).
2. Guardar a chave de quem paga o deploy (a chave é digitada no terminal, por você):
   `cast wallet import deployer --interactive`
3. **Simulação** (não envia nada, só confere): 
   `forge script script/Deploy.s.sol --rpc-url amoy --account deployer`
4. Deploy de verdade (gasta POL de teste): o mesmo comando com `--broadcast`.
   Os endereços são gravados em `../deployments/amoy.json`.
5. Depois de criar as pools, ligar a parte da exchange (precisa ser a carteira dona da Factory):
   `POOL_ADDRESSES=0x...,0x... forge script script/SetFeeProtocol.s.sol --rpc-url amoy --account owner --broadcast`

O que o `Deploy.s.sol` faz, em ordem: Factory → habilita a faixa de 0,01% (a original não vem com ela) →
NFTDescriptor (biblioteca) → descriptor (sem proxy) → NonfungiblePositionManager → SwapRouter → QuoterV2 →
passa a propriedade da Factory para `OWNER_ADDRESS` → confere tudo (se algo estiver errado, o script falha).

Sem `WRAPPED_NATIVE_ADDRESS`, ele cria um WPOL/WBNB **de teste** (`src/testnet/`). Em rede principal usa-se o oficial.
