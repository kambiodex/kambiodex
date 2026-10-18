// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

/// @title IERC20Metadata
/// @notice Parte opcional do padrão ERC-20 que traz nome, símbolo e casas decimais.
/// @dev Escrita do zero pela KAMBIODEX (substitui a interface UNLICENSED do periphery original).
///      Não inclui as funções de saldo e transferência: o descriptor só precisa de leitura.
interface IERC20Metadata {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}
