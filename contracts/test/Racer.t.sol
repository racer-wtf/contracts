// SPDX-License-Identifier: MIT

//  @
//   )
//  ( _m_
//   \ " /,~~.
//    `(''/.\)
//     .>' (_--,
//  _=/d  . ^\
// ~' \)-'   '
//   // |'
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "forge-std/StdError.sol";

import "../src/Racer.sol";

contract Racer2Test is Test {
    Racer market;

    event CycleCreated(
        address indexed creator,
        uint256 indexed id,
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    );

    function setUp() public {
        market = new Racer();
    }

    function testCreateCycle(
        uint256 startingBlock,
        uint256 blockLength,
        uint256 votePrice
    ) public {
        vm.assume(votePrice > 0);

        // assume no arithmetic overflow
        unchecked {
            vm.assume(startingBlock + blockLength >= startingBlock);
        }

        vm.startPrank(address(1));
        vm.expectEmit();
        emit CycleCreated(address(1), 0, startingBlock, blockLength, votePrice);
        market.createCycle(startingBlock, blockLength, votePrice);
        vm.stopPrank();
    }
}
