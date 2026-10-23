// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {KambiodexDeployer} from "../script/helpers/KambiodexDeployer.sol";
import {VerifyPolygon} from "../script/VerifyPolygon.s.sol";

/// @notice Testa o script de verificação pós-deploy numa cópia local (sem rede), com chainId 137.
contract VerifyPolygonTest is Test, KambiodexDeployer {
    address constant WPOL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant TREZOR = 0xcfaf6Cb6BF850B0088d675BEa655acf98017872E;

    function _setEnv(Deployed memory d) internal {
        vm.setEnv("FACTORY_ADDRESS", vm.toString(d.factory));
        vm.setEnv("DESCRIPTOR_ADDRESS", vm.toString(d.descriptor));
        vm.setEnv("POSITION_MANAGER_ADDRESS", vm.toString(d.positionManager));
        vm.setEnv("ROUTER_ADDRESS", vm.toString(d.router));
        vm.setEnv("QUOTER_ADDRESS", vm.toString(d.quoter));
    }

    /// (Um teste só, em sequência: variáveis de ambiente são compartilhadas entre testes paralelos.)
    function test_verify_okAndFailures() public {
        vm.chainId(137);
        // WPOL de teste no endereço real do WPOL (só nesta cópia local).
        address mock = _create("WrappedNativeTestnet.sol:WrappedNativeTestnet", abi.encode("Wrapped POL", "WPOL"));
        vm.etch(WPOL, mock.code);

        Deployed memory d = deployAll(WPOL, TREZOR);
        _setEnv(d);
        VerifyPolygon v = new VerifyPolygon();
        v.run(); // tudo certo: não pode reverter

        // Dono errado (a Factory continua com o deployer): tem de falhar.
        Deployed memory d2 = deployAll(WPOL, address(0));
        _setEnv(d2);
        VerifyPolygon v2 = new VerifyPolygon();
        vm.expectRevert("Verificacao FALHOU: veja os itens acima");
        v2.run();

        // Rede errada: falha.
        _setEnv(d);
        vm.chainId(80002);
        VerifyPolygon v3 = new VerifyPolygon();
        vm.expectRevert("Verificacao FALHOU: veja os itens acima");
        v3.run();
    }
}
