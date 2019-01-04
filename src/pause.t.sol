// Copyright (C) 2019 David Terry <me@xwvvvvwx.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.0 <0.6.0;

import "ds-test/test.sol";

import "./pause.sol";

contract Hevm {
    function warp(uint256) public;
}

contract Target {
    function getBytes32() public pure returns (bytes32) {
        return bytes32("Hello");
    }
}

contract Stranger {
    function call(address target, bytes memory data) public returns (bytes memory) {
        (bool success, bytes memory result) = target.call(data);

        require(success);
        return result;
    }
}

contract Test is DSTest {
    DSPause pause;
    Target target;
    Hevm hevm;
    Stranger stranger;

    uint256 start = 1;
    uint256 wait  = 1;
    uint256 ready = 3;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(start);

        target = new Target();
        pause = new DSPause(wait);
        stranger = new Stranger();
    }
}

contract Constructor is DSTest {

    function test_delay_set() public {
        DSPause pause = new DSPause(100);
        assertEq(pause.delay(), 100);
    }

    function test_creator_is_owner() public {
        DSPause pause = new DSPause(100);
        assertEq(pause.wards(address(this)), 1);
    }

    function test_not_frozen() public {
        DSPause pause = new DSPause(100);
        assertEq(pause.freezeUntil(), 0);
    }

}

contract Schedule is Test {

    function testFail_cannot_schedule_zero_address() public {
        pause.schedule(address(0), abi.encode(0));
    }

    function testFail_cannot_be_called_by_non_owner() public {
        stranger.call(address(pause), abi.encodeWithSignature("schedule(address,bytes)", address(0), abi.encode(0)));
    }

    function test_insertion() public {
        bytes memory dataIn = abi.encodeWithSignature("getBytes32()");

        bytes32 id = pause.schedule(address(target), dataIn);
        (address guy, bytes memory dataOut, uint256 timestamp) = pause.queue(id);

        assertEq0(dataIn, dataOut);
        assertEq(guy, address(target));
        assertEq(timestamp, now);
    }

}

contract Execute is Test {

    function testFail_delay_not_passed() public {
        bytes32 id = pause.schedule(address(target), abi.encode(0));
        pause.execute(id);
    }

    function testFail_double_execution() public {
        bytes32 id = pause.schedule(address(target), abi.encodeWithSignature("getBytes32()"));
        hevm.warp(ready);

        pause.execute(id);
        pause.execute(id);
    }

    function test_execute_delay_passed() public {
        bytes32 id = pause.schedule(address(target), abi.encodeWithSignature("getBytes32()"));
        hevm.warp(ready);

        bytes memory response = pause.execute(id);

        bytes32 response32;
        assembly {
            response32 := mload(add(response, 32))
        }
        assertEq(response32, bytes32("Hello"));
    }

    function test_call_from_non_owner() public {
        bytes32 id = pause.schedule(address(target), abi.encodeWithSignature("getBytes32()"));
        hevm.warp(ready);

        stranger.call(address(pause), abi.encodeWithSignature("execute(bytes32)", id));
    }

}
