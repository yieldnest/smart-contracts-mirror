import {MockERC4626} from "lib/yieldnest-vault/test/mainnet/mocks/MockERC4626.sol";
import {MockERC20} from "lib/yieldnest-vault/test/unit/mocks/MockERC20.sol";

import {Provider} from "src/module/Provider.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {IERC4626} from "lib/yieldnest-vault/src/Common.sol";

contract ProviderTest is Test {
    MockERC20 public mockERC20;
    MockERC4626 public mockERC4626;
    Provider public provider;

    address public owner = address(0xBEEF);

    function setUp() public {
        mockERC20 = new MockERC20("Mock Token", "MTKN");
        mockERC4626 = new MockERC4626(mockERC20, "Mock Vault", "MVLT");
        uint256 unitValue = 1e18;
        provider = new Provider(address(mockERC4626), unitValue);
        // Mint tokens to this test contract, then deposit them into the vault
        mockERC20.mint(10000e18);
        mockERC20.approve(address(mockERC4626), 10000e18);
        mockERC4626.deposit(10000e18, address(this));
    }

    function testReturnsUnitValueForUnderlyingAsset() public view {
        uint256 expectedRate = 1e18;
        address underlying = mockERC4626.asset();
        uint256 returned = provider.getRate(underlying);
        assertEq(returned, expectedRate, "Should return the fixed unit value for underlying asset");
    }

    function testReturnsConvertToAssetsForVault() public {
        uint256 unitValue = 1e18;
        // Prepare recipient for "donation" of vault shares to the vault itself (inflate TVL)
        // Step 1: Mint underlying to donor
        vm.startPrank(owner);
        mockERC20.mint(5000e18);
        // Step 2: Deposit as donor to receive vault shares

        mockERC20.approve(address(mockERC4626), 5000e18);
        uint256 shares = mockERC4626.deposit(5000e18, owner);
        // Step 3: Donate vault shares directly to the vault (simulate a donation)
        mockERC4626.transfer(address(mockERC4626), shares);
        vm.stopPrank();

        uint256 expected = mockERC4626.convertToAssets(unitValue);
        uint256 returned = provider.getRate(address(mockERC4626));
        assertEq(returned, expected, "Should return vault convertToAssets(unitValue) after donation to vault");
    }

    function testRevertsOnUnsupportedAsset() public {
        address fakeAsset = address(0xABCD1234);
        vm.expectRevert(abi.encodeWithSelector(Provider.UnsupportedAsset.selector, fakeAsset));
        provider.getRate(fakeAsset);
    }
}
