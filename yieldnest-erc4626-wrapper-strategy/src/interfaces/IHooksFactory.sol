// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {FeeHooks} from "lib/yieldnest-vault/src/hooks/FeeHooks.sol";
import {IHooks} from "lib/yieldnest-vault/src/interface/IHooks.sol";
import {IMetaHooks} from "src/interfaces/IMetaHooks.sol";

interface IHooksFactory {
    function createMetaHooks(address vault, address owner, address hookManager, IHooks[] memory hooks)
        external
        returns (IMetaHooks);

    function createProcessAccountingGuardHook(
        address vault,
        address owner,
        uint256 maxDecreaseRatio,
        uint256 maxIncreaseRatio,
        uint256 maxTotalSupplyIncreaseRatio,
        uint256 performanceFee
    ) external returns (IHooks);

    function createFeeHooks(address vault, address owner, uint256 performanceFee, address performanceFeeRecipient)
        external
        returns (IHooks);

    function FACTORY_VERSION() external view returns (string memory);
}
