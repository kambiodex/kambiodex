# KAMBIODEX — Plano de segurança

Versão 1.0 · outubro de 2026 · rede: Polygon PoS (fase 1)

## 1. Princípios

1. **Não alterar o código do Uniswap v3.** A maior parte dos hacks em cópias de DEX veio de mudanças no código original (ex.: Uranium Finance, 2021).
2. **Separar o que pode ser atacado:** contratos (blockchain), chaves (carteiras), domínio e site, servidor e dados.
3. **Nenhuma chave importante em computador, celular, nuvem ou repositório.**
4. **Detectar rápido e saber agir:** monitoramento automático e plano de incidente escrito antes do lançamento.

## 2. Contratos inteligentes

- [ ] Usar exatamente as versões oficiais de `v3-core` e `v3-periphery` (mesmo commit e compilador das implantações oficiais).
- [ ] Única alteração permitida: o necessário para publicar (ex.: `POOL_INIT_CODE_HASH`, endereço do WPOL).
- [ ] Comparar o bytecode publicado com o das implantações oficiais do Uniswap v3 (deve ser idêntico, exceto os parâmetros de construção).
- [ ] Verificar o código-fonte de todos os contratos na **Polygonscan**.
- [ ] Testar tudo na **Polygon Amoy** antes da rede principal (pools, faixas, coleta de taxas, `setFeeProtocol`, `collectProtocol`).
- [ ] Auditoria independente do processo de publicação, dos scripts e da configuração.
- [ ] Sem proxies e sem funções de atualização.
- [ ] Publicar no site uma página com os **endereços oficiais dos contratos**.

## 3. Chaves e carteiras

| Carteira | Para quê | Onde fica |
|---|---|---|
| **Deployer** | Só para publicar os contratos | Carteira nova, usada uma vez; depois esvaziada |
| **Owner** | `owner` da Factory: parte da exchange (1/6), `collectProtocol`, faixas de taxa | **Carteira física** (Ledger/Trezor), nunca conectada a sites desconhecidos |
| **Operação** | Liquidez inicial das pools da empresa | Carteira física separada |

- [ ] Após publicar, transferir a propriedade da Factory (`setOwner`) para a carteira **Owner** e conferir na Polygonscan.
- [ ] Frase de recuperação anotada em papel ou placa de metal, guardada em dois locais seguros. Nunca fotografar, digitar ou salvar na nuvem.
- [ ] **Coletar as taxas da exchange com frequência** (semanal ou ao atingir um valor-limite), para não acumular valor nas pools.
- [ ] Assinar transações do Owner só depois de conferir na tela da carteira física o contrato e a função.
- [ ] Avaliar no futuro passar o Owner para um cofre multiassinatura (ex.: Safe 2 de 3).

## 4. Domínio e DNS (www.kambiodex.com)

- [ ] Dynadot: 2FA por **aplicativo** (não SMS), bloqueio de transferência, privacidade WHOIS, renovação automática.
- [ ] E-mail exclusivo para as contas do projeto, também com 2FA por aplicativo.
- [ ] Cloudflare: 2FA, acesso só do dono, **DNSSEC ativado**, alertas de mudança de DNS e de certificados.
- [ ] HSTS ativado (o navegador só aceita o site com https).
- [ ] Redirecionamento 301 de `kambiodex.com` para `www.kambiodex.com`.

## 5. Site (front-end)

- [ ] GitHub: 2FA, ramo principal protegido, publicação só pelo processo automático (Cloudflare Pages ligado ao repositório).
- [ ] Dependências com versões travadas (`lockfile`) e alertas automáticos de vulnerabilidade.
- [ ] **Política de segurança de conteúdo (CSP)** restritiva: o site só carrega scripts próprios; nada de scripts de terceiros sem necessidade.
- [ ] Endereços dos contratos e dos tokens verificados **fixos na configuração**, nunca vindos de fora em tempo real.
- [ ] Toda transação mostra na tela o contrato, o valor mínimo recebido e o prazo antes de assinar.
- [ ] Nunca pedir aprovação ilimitada de token sem o usuário escolher (opção de aprovar só o valor da troca).
- [ ] Aviso permanente sobre sites falsos e o endereço oficial do site.

## 6. Servidor e dados (Cloudflare Workers + D1)

- [ ] Chaves de serviços (RPC, triagem de sanções) guardadas como **segredos** na Cloudflare, nunca no código.
- [ ] Banco D1 acessível só pelo Worker e pelo dono; registros de acesso apagados automaticamente após 6 meses (exceto preservação).
- [ ] Limite de requisições (rate limit) e proteção contra robôs nas funções do servidor.
- [ ] Registro de quem acessou o banco e quando.

## 7. Monitoramento e alertas

- [ ] Alertas automáticos (ex.: Tenderly ou Forta) para:
  - saída grande de liquidez de uma pool ou troca muito acima do normal;
  - qualquer chamada a `setOwner`, `setFeeProtocol`, `enableFeeAmount` ou `collectProtocol`;
  - movimentação da carteira Owner.
- [ ] Monitor de integridade do site: alerta se os arquivos publicados mudarem sem uma publicação autorizada.
- [ ] Alertas de mudança de DNS, de novo certificado emitido para o domínio e de sites com nome parecido.
- [ ] Os alertas chegam por e-mail e por aplicativo de mensagens do dono.

## 8. Programa de recompensa por falhas (bug bounty)

- [ ] Programa em plataforma especializada (ex.: Immunefi) ou próprio, com regras e valores claros.
- [ ] Escopo: site, servidor, configuração e scripts de publicação (os contratos são os do Uniswap v3, que já tem programa próprio).

## 9. Plano de incidente

**Os contratos não podem ser pausados.** O que a KAMBIODEX controla é o site, o servidor e a carteira Owner.

1. **Detectar e confirmar** (alerta ou relato) — anotar horário e evidências.
2. **Conter:**
   - site comprometido → ativar página de manutenção na Cloudflare em minutos;
   - chave do Owner suspeita → coletar as taxas e transferir a propriedade para uma carteira nova, se ainda possível;
   - domínio sequestrado → acionar o suporte da Dynadot e da Cloudflare.
3. **Avisar os usuários** nos canais oficiais (X, Telegram): o que aconteceu, o que não fazer, como **revogar aprovações** (ex.: revoke.cash) e quando o site volta.
4. **Investigar e corrigir** a causa antes de reabrir.
5. **Obrigações legais:** se houver vazamento de dados pessoais, comunicar a ANPD e os afetados no prazo da regulamentação (conferir o prazo atual com o advogado).
6. **Relatório final** público com o que aconteceu e o que mudou.

## 10. Checklist antes do lançamento

- [ ] Itens das seções 2 a 6 concluídos.
- [ ] Auditoria entregue e pontos corrigidos.
- [ ] Monitoramento ativo e testado (alerta de teste recebido).
- [ ] Plano de incidente revisado; página de manutenção pronta.
- [ ] Página de contratos oficiais publicada.
- [ ] Parecer jurídico concluído.

## 11. Rotina

| Frequência | O que fazer |
|---|---|
| Semanal | Coletar taxas da exchange; revisar alertas; conferir saldo da carteira Owner |
| Mensal | Atualizar dependências do site; revisar acessos na Cloudflare, GitHub e Dynadot |
| A cada mudança no site | Revisão do código e publicação só pelo processo automático |
| Anual | Testar o plano de incidente; revisar este documento |
