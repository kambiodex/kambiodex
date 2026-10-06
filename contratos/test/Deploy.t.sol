// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV3Deployer} from "../script/helpers/UniswapV3Deployer.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {INPM} from "./helpers/IPeriphery.sol";

interface IDescriptorWETH {
    function WETH9() external view returns (address);
}

/// @notice Testa o script de deploy (tudo em memória, nenhuma rede real é tocada).
contract DeployTest is Test, UniswapV3Deployer {
    address owner = makeAddr("owner");
    address wrapped;

    function setUp() public {
        wrapped = _create("WrappedNativeTestnet.sol:WrappedNativeTestnet", abi.encode("Wrapped POL", "WPOL"));
    }

    function test_deployAll_wiresEverything() public {
        Deployed memory d = deployAll(wrapped, owner);

        IUniswapV3Factory f = IUniswapV3Factory(d.factory);
        assertEq(f.owner(), owner); // dono passou para a carteira Owner
        assertEq(f.feeAmountTickSpacing(100), 1); // 0,01%
        assertEq(f.feeAmountTickSpacing(500), 10); // 0,05%
        assertEq(f.feeAmountTickSpacing(3000), 60); // 0,30%
        assertEq(f.feeAmountTickSpacing(10000), 200); // 1%

        INPM npm = INPM(d.positionManager);
        assertEq(npm.factory(), d.factory);
        assertEq(npm.WETH9(), wrapped);
        assertEq(IDescriptorWETH(d.descriptor).WETH9(), wrapped);
        assertGt(d.nftDescriptorLib.code.length, 0);
        assertGt(d.router.code.length, 0);
        assertGt(d.quoter.code.length, 0);
    }

    function test_deployAll_descriptorIsLinkedToLibrary() public {
        Deployed memory d = deployAll(wrapped, owner);
        // Se a ligação com a biblioteca estivesse errada, o marcador "__$" sobraria no código ou o
        // tokenURI falharia (isso é testado de ponta a ponta em Periphery.t.sol).
        bytes memory code = d.descriptor.code;
        bytes memory libAddr = abi.encodePacked(d.nftDescriptorLib);
        assertTrue(_contains(code, libAddr), "endereco da biblioteca ausente no descriptor");
    }

    function test_deployAll_keepsOwnerWhenNoFinalOwner() public {
        Deployed memory d = deployAll(wrapped, address(0));
        assertEq(IUniswapV3Factory(d.factory).owner(), address(this));
    }

    function test_deployAll_rejectsEmptyWrappedToken() public {
        vm.expectRevert("wrappedNative vazio");
        this.deployAll(address(0), owner);
    }

    // ------------------------------------------------------------- script Deploy

    function test_script_allowsOnlyTestnets() public {
        Deploy script = new Deploy();
        assertEq(script.networkName(80002), "amoy");
        assertEq(script.networkName(97), "bnb-testnet");
        assertEq(script.networkName(31337), "local");

        vm.expectRevert(); // Polygon: bloqueada
        script.networkName(137);
        vm.expectRevert(); // BNB Chain: bloqueada
        script.networkName(56);
        vm.expectRevert(); // Ethereum
        script.networkName(1);
    }

    function test_script_run_refusesMainnet() public {
        Deploy script = new Deploy();
        vm.chainId(137);
        vm.expectRevert();
        script.run();
        vm.chainId(56);
        vm.expectRevert();
        script.run();
    }

    /// (Um teste só, em sequência: variáveis de ambiente são compartilhadas entre testes paralelos.)
    function test_script_run_endToEnd_simulated() public {
        Deploy script = new Deploy();
        vm.chainId(80002);
        vm.setEnv("WRAPPED_NATIVE_ADDRESS", vm.toString(wrapped));

        // Sem OWNER_ADDRESS numa testnet: o script se recusa a rodar.
        vm.setEnv("OWNER_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.expectRevert("Defina OWNER_ADDRESS no .env");
        script.run();

        // Com OWNER_ADDRESS: roda até o fim. Simulação (sem --broadcast) não grava arquivo.
        vm.setEnv("OWNER_ADDRESS", vm.toString(owner));
        script.run();
        assertFalse(vm.exists(string.concat(vm.projectRoot(), "/../deployments/amoy.json")));
    }

    function test_script_addressesJson_hasAllFields() public {
        Deploy script = new Deploy();
        Deployed memory d = deployAll(wrapped, owner);
        vm.chainId(80002);
        string memory json = script.addressesJson(d, owner);

        assertEq(vm.parseJsonUint(json, ".chainId"), 80002);
        assertEq(vm.parseJsonAddress(json, ".UniswapV3Factory"), d.factory);
        assertEq(vm.parseJsonAddress(json, ".NonfungiblePositionManager"), d.positionManager);
        assertEq(vm.parseJsonAddress(json, ".SwapRouter"), d.router);
        assertEq(vm.parseJsonAddress(json, ".QuoterV2"), d.quoter);
        assertEq(vm.parseJsonAddress(json, ".NonfungibleTokenPositionDescriptor"), d.descriptor);
        assertEq(vm.parseJsonAddress(json, ".NFTDescriptor"), d.nftDescriptorLib);
        assertEq(vm.parseJsonAddress(json, ".WrappedNative"), wrapped);
        assertEq(vm.parseJsonAddress(json, ".owner"), owner);
        assertEq(vm.parseJsonBytes32(json, ".poolInitCodeHash"), POOL_INIT_CODE_HASH);
    }

    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        if (needle.length > hay.length) return false;
        for (uint256 i = 0; i + needle.length <= hay.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (hay[i + j] != needle[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }
}
