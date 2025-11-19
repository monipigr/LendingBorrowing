// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../lib/forge-std/src/Test.sol";
import "../src/LendingProtocol.sol";
import "../src/MockToken.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

contract LendingProtocolTest is Test {
    LendingProtocol public lendingProtocol;
    MockToken public usdc;
    MockToken public weth;
    MockToken public dai;

    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public liquidator;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant DEPOSIT_AMOUNT = 100 * 1e18;
    uint256 public constant BORROW_AMOUNT = 50 * 1e18;
    uint256 public constant INITIAL_LIQUIDITY = INITIAL_SUPPLY / 4;
    uint256 public constant COLLATERAL_FACTOR = 8_000; // 80%
    uint256 public constant SUPPLY_RATE = 500; // 5%
    uint256 public constant BORROW_RATE = 800; // 8%

    // Events
    event MarketAdded(address indexed token, uint256 collateralFactor);
    event MarketUpdated(address indexed token, uint256 collateralFactor);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event RatesUpdated(
        address indexed token,
        uint256 supplyRate,
        uint256 borrowRate
    );

    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        liquidator = makeAddr("liquidator");

        // Deploy contracts
        vm.startPrank(owner);
        lendingProtocol = new LendingProtocol();
        vm.stopPrank();

        // Deploy mock tokens contracts
        usdc = new MockToken("USD coin", "USDC", 18, INITIAL_SUPPLY);
        weth = new MockToken("WETH coin", "WETH", 18, INITIAL_SUPPLY);
        dai = new MockToken("DAI coin", "DAI", 18, INITIAL_SUPPLY);

        // Add markets
        vm.startPrank(owner);
        lendingProtocol.addMarket(
            address(usdc),
            COLLATERAL_FACTOR,
            SUPPLY_RATE,
            BORROW_RATE
        );
        lendingProtocol.addMarket(
            address(weth),
            COLLATERAL_FACTOR,
            SUPPLY_RATE,
            BORROW_RATE
        );
        lendingProtocol.addMarket(
            address(dai),
            COLLATERAL_FACTOR,
            SUPPLY_RATE,
            BORROW_RATE
        );
        vm.stopPrank();

        // Distribute tokens to users
        usdc.mint(user1, INITIAL_LIQUIDITY);
        weth.mint(user1, INITIAL_LIQUIDITY);
        dai.mint(user1, INITIAL_LIQUIDITY);

        usdc.mint(user2, INITIAL_LIQUIDITY);
        weth.mint(user2, INITIAL_LIQUIDITY);
        dai.mint(user2, INITIAL_LIQUIDITY);

        usdc.mint(user3, INITIAL_LIQUIDITY);
        weth.mint(user3, INITIAL_LIQUIDITY);
        dai.mint(user3, INITIAL_LIQUIDITY);

        usdc.mint(liquidator, INITIAL_LIQUIDITY);
        weth.mint(liquidator, INITIAL_LIQUIDITY);
        dai.mint(liquidator, INITIAL_LIQUIDITY);

        // Add initial liquidity to the protocol (only from user2 to leave user1 with tokens for testing)
        vm.startPrank(user2);
        usdc.approve(address(lendingProtocol), INITIAL_LIQUIDITY);
        weth.approve(address(lendingProtocol), INITIAL_LIQUIDITY);
        dai.approve(address(lendingProtocol), INITIAL_LIQUIDITY);

        lendingProtocol.deposit(address(usdc), INITIAL_LIQUIDITY);
        lendingProtocol.deposit(address(weth), INITIAL_LIQUIDITY);
        lendingProtocol.deposit(address(dai), INITIAL_LIQUIDITY);
        vm.stopPrank();
    }

    // ============ ADD MARKET TESTS ============

    function test_addMarket() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit MarketAdded(address(newToken), 7000);

        lendingProtocol.addMarket(address(newToken), 7000, 300, 800);
        vm.stopPrank();

        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(newToken)
        );
        assertTrue(market.isActive);
        assertEq(market.collateralFactor, 7000);
        assertEq(market.supplyRate, 300);
        assertEq(market.borrowRate, 800);
    }

    function test_addMarket_revertIfInvalidToken() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid token address");
        lendingProtocol.addMarket(address(0), 7000, 300, 800);
        vm.stopPrank();
    }

    function test_addMarket_revertIfInvalidCollateralFactor() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );

        vm.startPrank(owner);
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.addMarket(address(newToken), 70000, 300, 800);
        vm.stopPrank();
    }

    function test_addMarket_revertIfMarketAlreadyExists() public {
        vm.startPrank(owner);
        vm.expectRevert("Market already exists");
        lendingProtocol.addMarket(
            address(usdc),
            COLLATERAL_FACTOR,
            SUPPLY_RATE,
            BORROW_RATE
        );
        vm.stopPrank();
    }

    function test_addMarket_revertIfNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        lendingProtocol.addMarket(address(usdc), 7000, 300, 800);
        vm.stopPrank();
    }

    // ============ UPDATE MARKET TESTS ============

    function test_updateMarket() public {
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit MarketUpdated(address(usdc), 7000);

        vm.expectEmit(true, false, false, true);
        emit RatesUpdated(address(usdc), 400, 900);

        lendingProtocol.updateMarket(address(usdc), 7000, 400, 900);
        vm.stopPrank();

        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(usdc)
        );
        assertEq(market.collateralFactor, 7000);
        assertEq(market.supplyRate, 400);
        assertEq(market.borrowRate, 900);
    }

    function test_updateMarket_revertIfInvalidCollateralFactor() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.updateMarket(
            address(usdc),
            11000,
            SUPPLY_RATE,
            BORROW_RATE
        );
        vm.stopPrank();
    }

    function test_updateMarket_revertIfInactiveMarket() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );

        vm.startPrank(owner);
        vm.expectRevert("Market not active");
        lendingProtocol.updateMarket(
            address(newToken),
            7000,
            SUPPLY_RATE,
            BORROW_RATE
        );
        vm.stopPrank();
    }

    function test_updateMarket_revertIfNotOwner() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );

        vm.startPrank(user1);
        vm.expectRevert();
        lendingProtocol.updateMarket(
            address(newToken),
            7000,
            SUPPLY_RATE,
            BORROW_RATE
        );
        vm.stopPrank();
    }

    // ============ DEPOSIT TESTS ============
    function test_deposit() public {
        vm.startPrank(user1);

        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(usdc), DEPOSIT_AMOUNT);

        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        assertEq(
            lendingProtocol.getUserDeposit(user1, address(usdc)),
            DEPOSIT_AMOUNT
        );
        assertEq(lendingProtocol.getUser(user1).totalDeposited, DEPOSIT_AMOUNT);
        assertTrue(lendingProtocol.getUser(user1).isActive);

        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(usdc)
        );
        assertEq(market.totalSupply, INITIAL_LIQUIDITY + DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_deposit_revertIfZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.deposit(address(usdc), 0);

        vm.stopPrank();
    }

    function test_deposit_revertIfInactiveMarket() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );
        newToken.mint(user1, DEPOSIT_AMOUNT);

        vm.startPrank(user1);
        newToken.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert("Market not active");
        lendingProtocol.deposit(address(newToken), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_deposit_revertWhenPaused() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );
        newToken.mint(user1, DEPOSIT_AMOUNT);

        vm.prank(owner);
        lendingProtocol.pause();

        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert();
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    // ============ WITHDRAW TESTS ============

    function testWithdraw() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Withdraw(user1, address(usdc), DEPOSIT_AMOUNT / 2);

        // Withdraw
        lendingProtocol.withdraw(address(usdc), DEPOSIT_AMOUNT / 2);

        assertEq(
            lendingProtocol.getUserDeposit(user1, address(usdc)),
            DEPOSIT_AMOUNT / 2
        );
        assertEq(
            lendingProtocol.getUser(user1).totalDeposited,
            DEPOSIT_AMOUNT / 2
        );

        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(usdc)
        );
        assertEq(market.totalSupply, INITIAL_LIQUIDITY + DEPOSIT_AMOUNT / 2);

        vm.stopPrank();
    }

    function test_withdraw_revertIfZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.withdraw(address(usdc), 0);

        vm.stopPrank();
    }

    function test_withdraw_revertIfInsufficientDeposit() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        vm.expectRevert("Insufficient deposit");
        lendingProtocol.withdraw(address(usdc), DEPOSIT_AMOUNT + 1);

        vm.stopPrank();
    }

    function test_withdraw_revertIfUnsafePosition() public {
        // Setup: user deposits USDC and borrows DAI
        vm.startPrank(user1);

        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        dai.approve(address(lendingProtocol), BORROW_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);

        // Try to withdraw too much (would make position unsafe)
        vm.expectRevert("Withdrawal would make the position unsafe");
        lendingProtocol.withdraw(address(usdc), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_withdraw_revertIfInactiveMarket() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );
        newToken.mint(user1, DEPOSIT_AMOUNT);

        vm.startPrank(user1);

        newToken.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert("Market not active");
        lendingProtocol.withdraw(address(newToken), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function test_withdraw_revertWhenPaused() public {
        vm.prank(owner);
        lendingProtocol.pause();

        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert();
        lendingProtocol.withdraw(address(usdc), DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    // ============ BORROW TESTS ============

    function test_borrow() public {
        // First deposit collateral
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        // Then borrow
        vm.expectEmit(true, true, false, true);
        emit Borrow(user1, address(dai), BORROW_AMOUNT);

        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);

        assertEq(
            lendingProtocol.getUserBorrow(user1, address(dai)),
            BORROW_AMOUNT
        );
        assertEq(lendingProtocol.getUser(user1).totalBorrowed, BORROW_AMOUNT);
        assertTrue(lendingProtocol.getUser(user1).isActive);

        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(dai)
        );
        assertEq(market.totalBorrow, BORROW_AMOUNT);

        vm.stopPrank();
    }

    function test_borrow_revertIfZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.borrow(address(dai), 0);

        vm.stopPrank();
    }

    function test_borrow_revertIfInsufficientLiquidity() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);

        // Try to borrow more than available liquidity
        vm.expectRevert("Insufficient liquidity");
        lendingProtocol.borrow(address(dai), INITIAL_LIQUIDITY + 1);

        vm.stopPrank();
    }

    function test_borrow_revertWhenPaused() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.prank(owner);
        lendingProtocol.pause();

        vm.expectRevert();
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);

        vm.stopPrank();
    }

    // ============ REPAY TESTS ============

    function test_repay() public {
        // Setup: user deposits and borrows
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);
        vm.stopPrank();

        // Repay
        vm.startPrank(user1);
        dai.approve(address(lendingProtocol), BORROW_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Repay(user1, address(dai), BORROW_AMOUNT);

        lendingProtocol.repay(address(dai), BORROW_AMOUNT);

        assertEq(lendingProtocol.getUserBorrow(user1, address(dai)), 0);
        assertEq(lendingProtocol.getUser(user1).totalBorrowed, 0);

        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(dai)
        );
        assertEq(market.totalBorrow, 0);

        vm.stopPrank();
    }

    function test_repay_revertIfZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user1);
        dai.approve(address(lendingProtocol), BORROW_AMOUNT);

        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.repay(address(dai), 0);

        vm.stopPrank();
    }

    function test_repay_revertIfInsufficientBorrow() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user1);
        dai.approve(address(lendingProtocol), BORROW_AMOUNT);

        vm.expectRevert("Insufficient borrow");
        lendingProtocol.repay(address(dai), BORROW_AMOUNT + 1);

        vm.stopPrank();
    }

    function test_repay_revertIfNotActiveMarket() public {
        MockToken newToken = new MockToken(
            "New Token",
            "NEW",
            18,
            INITIAL_SUPPLY
        );
        newToken.mint(user1, BORROW_AMOUNT);

        vm.startPrank(user1);
        newToken.approve(address(lendingProtocol), BORROW_AMOUNT);

        vm.expectRevert("Market not active");
        lendingProtocol.repay(address(newToken), BORROW_AMOUNT);

        vm.stopPrank();
    }

    function test_repay_revertWhenPaused() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);

        dai.approve(address(lendingProtocol), BORROW_AMOUNT);
        vm.stopPrank();

        vm.prank(owner);
        lendingProtocol.pause();

        vm.expectRevert();
        lendingProtocol.repay(address(dai), BORROW_AMOUNT);

        vm.stopPrank();
    }

    // ============ SIGNATURE VERIFICATION TESTS ============

    function test_depositWithSignature_revertIfExpired() public {
        vm.startPrank(user1);

        uint256 nonce = lendingProtocol.getNonce(user1);
        uint256 deadline = block.timestamp - 1; // Expired

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "deposit",
                address(usdc),
                DEPOSIT_AMOUNT,
                nonce,
                deadline
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            user1PrivateKey(),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        LendingProtocol.SignatureData memory sigData = LendingProtocol
            .SignatureData({
                nonce: nonce,
                deadline: deadline,
                signature: signature
            });

        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert("Signature expired");
        lendingProtocol.depositWithSignature(
            address(usdc),
            DEPOSIT_AMOUNT,
            sigData
        );

        vm.stopPrank();
    }

    function test_depositWithSignature_revertIfInvalidNonce() public {
        vm.startPrank(user1);

        uint256 nonce = lendingProtocol.getNonce(user1) + 1; // Wrong nonce
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "deposit",
                address(usdc),
                DEPOSIT_AMOUNT,
                nonce,
                deadline
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            user1PrivateKey(),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        LendingProtocol.SignatureData memory sigData = LendingProtocol
            .SignatureData({
                nonce: nonce,
                deadline: deadline,
                signature: signature
            });

        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert("Invalid nonce");
        lendingProtocol.depositWithSignature(
            address(usdc),
            DEPOSIT_AMOUNT,
            sigData
        );

        vm.stopPrank();
    }

    function test_depositWithSignature_revertIfInvalidSignature() public {
        vm.startPrank(user1);

        uint256 nonce = lendingProtocol.getNonce(user1);
        uint256 deadline = block.timestamp + 1 hours;

        // Use wrong signer
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "deposit",
                address(usdc),
                DEPOSIT_AMOUNT,
                nonce,
                deadline
            )
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            user2PrivateKey(),
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        LendingProtocol.SignatureData memory sigData = LendingProtocol
            .SignatureData({
                nonce: nonce,
                deadline: deadline,
                signature: signature
            });

        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);

        vm.expectRevert("Invalid signature");
        lendingProtocol.depositWithSignature(
            address(usdc),
            DEPOSIT_AMOUNT,
            sigData
        );

        vm.stopPrank();
    }

    // ============ LIQUIDATION TESTS ============
    // function test_liquidate() public {

    // }

    function test_liquidate_revertIfZeroAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.liquidate(user1, address(dai), 0);
    }

    function test_liquidate_revertIfInsufficientBorrow() public {
        vm.startPrank(liquidator);
        dai.approve(address(lendingProtocol), BORROW_AMOUNT);

        vm.expectRevert("Insufficient borrow to liquidate");
        lendingProtocol.liquidate(user1, address(dai), BORROW_AMOUNT);

        vm.stopPrank();
    }

    function test_liquidate_revertIfNotLiquidatable() public {
        vm.startPrank(user1);

        usdc.approve(address(lendingProtocol), 10_000e6);
        lendingProtocol.deposit(address(usdc), 10_000e6);

        lendingProtocol.borrow(address(dai), 100e18);

        vm.stopPrank();

        vm.startPrank(liquidator);
        dai.approve(address(lendingProtocol), 100e18);

        vm.expectRevert("Position is not liquidatable");
        lendingProtocol.liquidate(user1, address(dai), 100e18);

        vm.stopPrank();
    }

    function test_liquidate_revertIfNotActiveMarket() public {
        MockToken fakeToken = new MockToken("Fake", "FAKE", 18, 1e24);

        vm.expectRevert("Market not active");
        lendingProtocol.liquidate(user1, address(fakeToken), 100e18);
    }

    function test_liquidate_revertWhenPaused() public {
        vm.prank(owner);
        lendingProtocol.pause();

        vm.expectRevert();
        lendingProtocol.liquidate(user1, address(dai), 100e18);
    }

    function _getUserDepositSlot(
        address user,
        address token
    ) internal pure returns (bytes32) {
        uint256 slot = 1; // userDeposits is storage slot 1

        bytes32 slotUser = keccak256(abi.encode(user, slot));
        bytes32 slotToken = keccak256(abi.encode(token, slotUser));

        return slotToken;
    }

    function test_isLiquidatable() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), 1000e18);
        lendingProtocol.deposit(address(usdc), 1000e18);

        lendingProtocol.borrow(address(dai), 800e18);
        vm.stopPrank();

        bytes32 slot = _getUserDepositSlot(user1, address(usdc));
        vm.store(address(lendingProtocol), slot, bytes32(uint256(100e18)));

        assertTrue(lendingProtocol.isLiquidatable(user1));
    }

    function test_liquidate() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), 1000e18);
        lendingProtocol.deposit(address(usdc), 1000e18);

        lendingProtocol.borrow(address(dai), 800e18);
        vm.stopPrank();

        bytes32 slot = _getUserDepositSlot(user1, address(usdc));
        vm.store(address(lendingProtocol), slot, bytes32(uint256(100e18)));

        assertTrue(lendingProtocol.isLiquidatable(user1));

        vm.startPrank(liquidator);
        dai.approve(address(lendingProtocol), 100e18);

        lendingProtocol.liquidate(user1, address(dai), 100e18);

        vm.stopPrank();

        assertEq(
            lendingProtocol.getUserBorrow(user1, address(dai)),
            800e18 - 100e18
        );
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_getCollateralizationRatio() public {
        // User with no borrows should return max value
        assertEq(
            lendingProtocol.getCollateralizationRatio(user1),
            type(uint256).max
        );

        // User with deposits and borrows
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);
        vm.stopPrank();

        uint256 ratio = lendingProtocol.getCollateralizationRatio(user1);
        assertGt(ratio, 0);
    }

    function test_canWithdraw() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Should be able to withdraw small amount
        assertTrue(
            lendingProtocol.canWithdraw(
                user1,
                address(usdc),
                DEPOSIT_AMOUNT / 4
            )
        );

        // Should not be able to withdraw too much (this would make position unsafe)
        // First borrow some tokens to create a position
        vm.startPrank(user1);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);
        vm.stopPrank();

        assertFalse(
            lendingProtocol.canWithdraw(user1, address(usdc), DEPOSIT_AMOUNT)
        );
    }

    function test_canBorrow() public {
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertTrue(
            lendingProtocol.canBorrow(user1, address(dai), BORROW_AMOUNT)
        );

        vm.startPrank(user1);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT / 4);
        vm.stopPrank();

        assertTrue(
            lendingProtocol.canBorrow(user1, address(dai), BORROW_AMOUNT / 4)
        );

        assertFalse(
            lendingProtocol.canBorrow(user1, address(dai), DEPOSIT_AMOUNT * 10)
        );
    }

    function test_getNonce() public {
        assertEq(lendingProtocol.getNonce(user1), 0);

        vm.startPrank(user1);

        LendingProtocol.SignatureData memory sig;
        sig.nonce = 0;
        sig.deadline = block.timestamp + 1;
        sig.signature = hex"00";
        vm.expectRevert();
        lendingProtocol.depositWithSignature(address(usdc), 0, sig);

        vm.stopPrank();

        assertEq(lendingProtocol.getNonce(user1), 0);
    }

    function test_getMarket() public view {
        LendingProtocol.Market memory market = lendingProtocol.getMarket(
            address(usdc)
        );
        assertTrue(market.isActive);
        assertEq(market.collateralFactor, COLLATERAL_FACTOR);
        assertEq(market.supplyRate, SUPPLY_RATE);
        assertEq(market.borrowRate, BORROW_RATE);
        assertEq(market.totalSupply, INITIAL_LIQUIDITY);
    }

    function test_getUser() public {
        LendingProtocol.User memory user = lendingProtocol.getUser(user1);
        assertEq(user.totalDeposited, 0);
        assertEq(user.totalBorrowed, 0);
        assertFalse(user.isActive);

        // After deposit, user should be active
        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        user = lendingProtocol.getUser(user1);
        assertEq(user.totalDeposited, DEPOSIT_AMOUNT);
        assertTrue(user.isActive);
    }

    function test_getUserDeposit() public {
        assertEq(lendingProtocol.getUserDeposit(user1, address(usdc)), 0);

        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(
            lendingProtocol.getUserDeposit(user1, address(usdc)),
            DEPOSIT_AMOUNT
        );
    }

    function test_getUserBorrow() public {
        assertEq(lendingProtocol.getUserBorrow(user1, address(dai)), 0);

        vm.startPrank(user1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(dai), BORROW_AMOUNT);
        vm.stopPrank();

        assertEq(
            lendingProtocol.getUserBorrow(user1, address(dai)),
            BORROW_AMOUNT
        );
    }

    function test_getSupportedTokens() public view {
        address[] memory tokens = lendingProtocol.getSupportedTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(usdc));
        assertEq(tokens[1], address(weth));
        assertEq(tokens[2], address(dai));
    }

    // ============ ADMIN FUNCTION TESTS ============

    function test_pause() public {
        vm.startPrank(owner);
        lendingProtocol.pause();
        vm.stopPrank();
        assertTrue(lendingProtocol.paused());
    }

    function test_unpause() public {
        vm.startPrank(owner);
        lendingProtocol.pause();
        lendingProtocol.unpause();
        vm.stopPrank();
        assertFalse(lendingProtocol.paused());
    }

    // ============ HELPER FUNCTIONS ============

    function user1PrivateKey() internal pure returns (uint256) {
        return
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    }

    function user2PrivateKey() internal pure returns (uint256) {
        return
            0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    }

    // ============ MOCK FUNCTIONS ============
    function test_burn() public {
        address tokenOwner = usdc.owner();
        vm.prank(tokenOwner);
        usdc.mint(user1, 1000 * 1e18);

        uint256 beforeBalance = usdc.balanceOf(user1);

        vm.prank(user1);
        usdc.burn(500 * 1e18);

        uint256 afterBalance = usdc.balanceOf(user1);

        assertEq(afterBalance, beforeBalance - 500 * 1e18);
    }

    function test_decimals() public view {
        assert(usdc.decimals() == 18);
    }
}
