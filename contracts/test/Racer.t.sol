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

    function setUp() public {
        market = new Racer();
    }
}
