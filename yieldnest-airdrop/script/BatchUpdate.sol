// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { console } from "forge-std/console.sol";
import { Airdrop, UserAmount } from "src/Airdrop.sol";

contract BatchUpdate {
    function updateUserAmountsInBatches(
        Airdrop _airdrop,
        UserAmount[] memory _userAmounts,
        uint256 _batchSize
    )
        internal
    {
        uint256 total = _userAmounts.length;
        if (total == 0) {
            console.log("No user amounts to update.");
            return;
        }

        uint256 numBatches = total / _batchSize;
        if (total % _batchSize != 0) {
            numBatches++;
        }

        console.log("Starting batch update...");
        console.log("Total user amounts:", total);
        console.log("Batch size:", _batchSize);
        console.log("Total batches:", numBatches);
        console.log("");

        for (uint256 i = 0; i < numBatches; i++) {
            uint256 start = i * _batchSize;
            uint256 end = start + _batchSize;
            if (end > total) {
                end = total;
            }

            console.log("Processing batch", i + 1);
            console.log(" - Range: [%s, %s)", start, end);

            UserAmount[] memory tempUserAmounts = new UserAmount[](end - start);
            for (uint256 j = 0; j < end - start; j++) {
                tempUserAmounts[j] = _userAmounts[start + j];
            }

            _airdrop.updateUserAmounts(tempUserAmounts);

            console.log(" - Batch", i + 1, "completed");
            console.log("");
        }

        console.log("All batches processed.");
    }
}
