// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseAssetProvider} from "src/provider/BaseAssetProvider.sol";

contract BaseAssetProviderTest is Test {
    address private constant BASE_ASSET = address(0xBA5E);
    address private constant DEFAULT_ASSET = address(0xDEF);
    address private constant UNSUPPORTED_ASSET = address(0xBAD);
    uint256 private constant RATE = 1e18;

    function testConstructorStoresAssetsAndRate() public {
        BaseAssetProvider provider = new BaseAssetProvider(BASE_ASSET, DEFAULT_ASSET, RATE);

        assertEq(provider.baseAsset(), BASE_ASSET);
        assertEq(provider.defaultAsset(), DEFAULT_ASSET);
        assertEq(provider.rate(), RATE);
    }

    function testGetRateReturnsRateForBaseAsset() public {
        BaseAssetProvider provider = new BaseAssetProvider(BASE_ASSET, DEFAULT_ASSET, RATE);

        assertEq(provider.getRate(BASE_ASSET), RATE);
    }

    function testGetRateReturnsRateForDefaultAsset() public {
        BaseAssetProvider provider = new BaseAssetProvider(BASE_ASSET, DEFAULT_ASSET, RATE);

        assertEq(provider.getRate(DEFAULT_ASSET), RATE);
    }

    function testGetRateReturnsRateWhenAssetsAreSame() public {
        BaseAssetProvider provider = new BaseAssetProvider(BASE_ASSET, BASE_ASSET, RATE);

        assertEq(provider.baseAsset(), BASE_ASSET);
        assertEq(provider.defaultAsset(), BASE_ASSET);
        assertEq(provider.getRate(BASE_ASSET), RATE);
    }

    function testGetRateRevertsForUnsupportedAsset() public {
        BaseAssetProvider provider = new BaseAssetProvider(BASE_ASSET, DEFAULT_ASSET, RATE);

        vm.expectRevert(abi.encodeWithSelector(BaseAssetProvider.UnsupportedAsset.selector, UNSUPPORTED_ASSET));
        provider.getRate(UNSUPPORTED_ASSET);
    }

    function testConstructorRevertsForZeroBaseAsset() public {
        vm.expectRevert(BaseAssetProvider.ZeroAddress.selector);
        new BaseAssetProvider(address(0), DEFAULT_ASSET, RATE);
    }

    function testConstructorRevertsForZeroDefaultAsset() public {
        vm.expectRevert(BaseAssetProvider.ZeroAddress.selector);
        new BaseAssetProvider(BASE_ASSET, address(0), RATE);
    }
}
