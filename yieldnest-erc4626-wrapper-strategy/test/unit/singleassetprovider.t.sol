import {MockERC4626} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";

import {SingleAssetProvider} from "src/module/SingleAssetProvider.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";

contract SingleAssetProviderTest is Test {
    MockERC20 public mockERC20;
    SingleAssetProvider public provider;

    address public owner = address(0xBEEF);

    function setUp() public {
        mockERC20 = new MockERC20("Mock Token", "MTKN");
        uint256 unitValue = 1e18;
        provider = new SingleAssetProvider(address(mockERC20), unitValue);
        // Mint tokens just to set up an asset, though not needed for SingleAssetProvider
        mockERC20.mint(10000e18);
    }

    function testReturnsUnitValueForUnderlyingAsset() public view {
        uint256 expectedRate = 1e18;
        address underlying = address(mockERC20);
        uint256 returned = provider.getRate(underlying);
        assertEq(returned, expectedRate, "Should return the fixed unit value for underlying asset");
    }

    function testRevertsOnUnsupportedAsset() public {
        address fakeAsset = address(0xABCD1234);
        vm.expectRevert(abi.encodeWithSelector(SingleAssetProvider.UnsupportedAsset.selector, fakeAsset));
        provider.getRate(fakeAsset);
    }

    function testProviderWithRandomUnitValue() public {
        uint256 newUnitValue = 12345;
        SingleAssetProvider newProvider = new SingleAssetProvider(address(mockERC20), newUnitValue);

        uint256 returned = newProvider.getRate(address(mockERC20));
        assertEq(returned, newUnitValue, "Should return the specified unit value for underlying asset");
    }
}
