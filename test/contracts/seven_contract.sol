pragma solidity ^0.4.0;

import "seven_library.sol";

contract SevenContract {
    function test() returns (int256 seven) {
        seven = SevenLibrary.seven();
    }
}
