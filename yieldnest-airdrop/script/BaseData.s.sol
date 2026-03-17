// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/Script.sol";

contract BaseData is Script {
    struct Data {
        address airdropOwner;
        address proxyAdminOwner;
    }

    struct ChainIds {
        uint256 mainnet;
        uint256 holesky;
        uint256 anvil;
        uint256 base;
        uint256 bnb;
    }

    mapping(uint256 chainId => Data data) private __data;

    ChainIds public chainIds = ChainIds({ mainnet: 1, holesky: 17_000, anvil: 31_337, base: 8453, bnb: 56 });

    address public constant YN_SECURITYCOUNCIL_MAINNET = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant YN_SECURITYCOUNCIL_HOLESKY = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;
    address public constant YN_SECURITYCOUNCIL_BNB = 0x721688652DEa9Cabec70BD99411EAEAB9485d436;

    // test only
    address public constant YN_SECURITYCOUNCIL_TEST_BASE = 0x0d4ae80207c30E5489976d62661882A995b52155;

    function setUp() public virtual {
        __data[chainIds.mainnet] =
            Data({ airdropOwner: YN_SECURITYCOUNCIL_MAINNET, proxyAdminOwner: YN_SECURITYCOUNCIL_MAINNET });

        __data[chainIds.holesky] =
            Data({ airdropOwner: YN_SECURITYCOUNCIL_HOLESKY, proxyAdminOwner: YN_SECURITYCOUNCIL_HOLESKY });
        __data[chainIds.base] =
            Data({ airdropOwner: YN_SECURITYCOUNCIL_TEST_BASE, proxyAdminOwner: YN_SECURITYCOUNCIL_TEST_BASE });
        __data[chainIds.bnb] =
            Data({ airdropOwner: YN_SECURITYCOUNCIL_BNB, proxyAdminOwner: YN_SECURITYCOUNCIL_BNB });
    }

    function getData(uint256 chainId) internal view returns (Data memory) {
        return __data[chainId];
    }

    function isSupportedChainId(uint256 chainId) internal view returns (bool) {
        return chainId == chainIds.mainnet || chainId == chainIds.holesky || chainId == chainIds.base
            || chainId == chainIds.bnb;
    }
}
