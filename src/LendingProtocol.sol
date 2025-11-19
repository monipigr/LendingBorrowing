// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

/**
Upgrades: 
- Separar contratos para separar responsabilidades y por tanto aumentar escalabilidad
- Factory. Tener un SC LendingFactory para que se puedan crear markets separados por cada SC, con sus características particulares como liquidations_threshold, liquidation_penalty, etc
- Lógica para que el Lender gane rewards por depositar ahí sus tokens, como staking o yieldFarming. 
- Poner un número máximo de markets que se pueden crear, para que los bucles for no sean demasiado grandes
 */

/**
 * @title LendingProtocol
 * @dev A DeFi lending and borrowing protocol that allows users to:
 * - Deposit tokens to earn interest
 * - Borrow tokens against their deposited collateral
 * - Use off-chain signatures for gasless operations
 * - Manage collateralization ratios and liquidation
 */
contract LendingProtocol is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct User {
        uint256 totalDeposited; // Total amount of deposited tokens by user
        uint256 totalBorrowed; // Total amount of borrowed tokens by user
        uint256 lastUpdateTime; // Last time user's data was updated
        bool isActive; // Whether the user has active positions or not
    }

    struct Market {
        IERC20 token; // Token being lent or borrowed
        uint256 totalSupply; // Total amount supplied to this market
        uint256 totalBorrow; // Total amount borrowed from this market
        uint256 supplyRate; // Current supply rate (APY in basis points)
        uint256 borrowRate; // Current borrow rate (APY in basis points)
        uint256 collateralFactor; // Collateral factor in bps (0 - 10000, where 10000 = 100%)
        bool isActive; // Whether the market is active or not
    }

    struct SignatureData {
        uint256 nonce; // Unique identifier for the signature
        uint256 deadline; // Signature expiration time
        bytes signature; // ECDSA signature
    }

    mapping(address => User) public users;
    mapping(address => mapping(address => uint256)) public userDeposits; // user => token => amount
    mapping(address => mapping(address => uint256)) public userBorrows; // user => token => amount
    mapping(address => Market) public markets;
    mapping(address => uint256) public userNonces;

    address[] supportedTokens;
    uint256 public constant LIQUIDATION_THRESHOLD = 8_000; // 80% in basis points
    uint256 public constant LIQUIDATION_PENALTY = 500; // 5% in basis points
    uint256 public constant BASIS_POINTS = 10_000; // 100% in basis pints

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

    modifier onlyActiveMarkets(address token) {
        require(markets[token].isActive, "Market not active");
        _;
    }

    modifier onlyValidSignature(SignatureData calldata sigData) {
        require(block.timestamp <= sigData.deadline, "Signature expired");
        require(userNonces[msg.sender] == sigData.nonce, "Invalid nonce");
        _;
        userNonces[msg.sender]++;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add a new market to the protocol
     * @param token The ERC20 token to add
     * @param collateralFactor The collateral factor for this token (0-10000)
     * @param initialSupplyRate Initial supply rate in basis points
     * @param initialBorrowRate Initial borrow rate in basis points
     */
    function addMarket(
        address token,
        uint256 collateralFactor,
        uint256 initialSupplyRate,
        uint256 initialBorrowRate
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(collateralFactor <= BASIS_POINTS, "Invalid collateral factor");
        require(!markets[token].isActive, "Market already exists");

        markets[token] = Market({
            token: IERC20(token),
            totalSupply: 0,
            totalBorrow: 0,
            supplyRate: initialSupplyRate,
            borrowRate: initialBorrowRate,
            collateralFactor: collateralFactor,
            isActive: true
        });

        supportedTokens.push(token);

        emit MarketAdded(token, collateralFactor);
    }

    /**
     * @dev Update market parameters
     * @param token The token address
     * @param collateralFactor New collateral factor
     * @param supplyRate New supply rate
     * @param borrowRate New borrow rate
     */
    function updateMarket(
        address token,
        uint256 collateralFactor,
        uint256 supplyRate,
        uint256 borrowRate
    ) external onlyOwner onlyActiveMarkets(token) {
        require(collateralFactor <= BASIS_POINTS, "Invalid collateral factor");

        markets[token].collateralFactor = collateralFactor;
        markets[token].supplyRate = supplyRate;
        markets[token].borrowRate = borrowRate;

        emit MarketUpdated(token, collateralFactor);
        emit RatesUpdated(token, supplyRate, borrowRate);
    }

    /**
     * @dev Deposit tokens to earn interest
     * @param token The token to deposit
     * @param amount The amount to deposit
     */
    function deposit(
        address token,
        uint256 amount
    ) external nonReentrant onlyActiveMarkets(token) whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        users[msg.sender].totalDeposited += amount;
        users[msg.sender].lastUpdateTime = block.timestamp;
        users[msg.sender].isActive = true;
        markets[token].totalSupply += amount;
        userDeposits[msg.sender][token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @dev Withdraw deposited tokens
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdraw(
        address token,
        uint256 amount
    ) external nonReentrant onlyActiveMarkets(token) whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(
            userDeposits[msg.sender][token] >= amount,
            "Insufficient deposit"
        );
        require(
            canWithdraw(msg.sender, token, amount),
            "Withdrawal would make the position unsafe"
        );

        users[msg.sender].totalDeposited -= amount;
        users[msg.sender].lastUpdateTime = block.timestamp;
        markets[token].totalSupply -= amount;
        userDeposits[msg.sender][token] -= amount;

        if (userDeposits[msg.sender][token] == 0) {
            users[msg.sender].isActive = false;
        }

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, token, amount);
    }

    /**
     * @dev Borrow tokens against deposited collateral
     * @param token The token to borrow
     * @param amount The amount to borrow
     */
    function borrow(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyActiveMarkets(token) {
        require(amount > 0, "Amount must be greater than 0");
        require(markets[token].totalSupply >= amount, "Insufficient liquidity");
        require(
            canBorrow(msg.sender, token, amount),
            "Borrow would exceed collateral limit"
        );

        users[msg.sender].totalBorrowed += amount;
        users[msg.sender].lastUpdateTime = block.timestamp;
        users[msg.sender].isActive = true;
        markets[token].totalBorrow += amount;
        userBorrows[msg.sender][token] += amount;

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, token, amount);
    }

    /**
     * @dev Repay borrowed tokens
     * @param token The token to repay
     * @param amount The amount to repay
     */
    function repay(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyActiveMarkets(token) {
        require(amount > 0, "Amount must be greater than 0");
        require(
            users[msg.sender].totalBorrowed >= amount,
            "Insufficient borrow"
        );
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        users[msg.sender].totalBorrowed -= amount;
        users[msg.sender].lastUpdateTime = block.timestamp;
        markets[token].totalBorrow -= amount;
        userBorrows[msg.sender][token] -= amount;
        if (users[msg.sender].totalBorrowed == 0) {
            users[msg.sender].isActive = false;
        }

        emit Repay(msg.sender, token, amount);
    }

    /**
     * @dev Liquidate an undercollateralized position
     * @param user The user to liquidate
     * @param token The token to liquidate
     * @param amount The amount to liquidate
     */
    function liquidate(
        address user,
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyActiveMarkets(token) {
        require(amount > 0, "Amount must be greater than 0");
        require(
            userBorrows[user][token] >= amount,
            "Insufficient borrow to liquidate"
        );
        require(isLiquidatable(user), "Position is not liquidatable");
        uint256 collateralToSeize = (amount *
            (BASIS_POINTS + LIQUIDATION_PENALTY)) / BASIS_POINTS;
        // Find collateral to seize
        address collateralToken = findBestCollateral(user);
        require(collateralToken != address(0), "No collateral to seize");
        require(
            userDeposits[user][collateralToken] >= collateralToSeize,
            "Insufficient collatera"
        );

        // Transfer borrowed tokens from liquidator
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update user's borrow
        users[user].totalBorrowed -= amount;
        markets[token].totalBorrow -= amount;
        userBorrows[user][token] -= amount;

        // Update seize collateral token
        userDeposits[user][collateralToken] -= collateralToSeize;
        users[user].totalDeposited -= collateralToSeize;
        markets[collateralToken].totalSupply -= collateralToSeize;

        // Transfer collateral to liquidator
        IERC20(collateralToken).safeTransfer(msg.sender, collateralToSeize);

        emit Liquidate(msg.sender, user, token, amount);
    }

    /**
     * @dev Gasless deposit using off-chain signature
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param sigData Signature data for verification
     */
    function depositWithSignature(
        address token,
        uint256 amount,
        SignatureData calldata sigData
    )
        external
        nonReentrant
        whenNotPaused
        onlyActiveMarkets(token)
        onlyValidSignature(sigData)
    {
        require(amount > 0, "Amount must be greater than 0");

        // Verify signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "deposit",
                token,
                amount,
                sigData.nonce,
                sigData.deadline
            )
        );

        bytes32 ethSignedMessage = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = ethSignedMessage.recover(sigData.signature);
        require(signer == msg.sender, "Invalid signature");
        require(signer != address(0), "Invalid signature2");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        users[msg.sender].totalDeposited += amount;
        users[msg.sender].lastUpdateTime = block.timestamp;
        users[msg.sender].isActive = true;
        markets[token].totalSupply += amount;
        userDeposits[msg.sender][token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @dev Check if a user can withdraw without making position unsafe
     * @param user The user address
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @return True if withdrawal is safe
     */
    function canWithdraw(
        address user,
        address token,
        uint256 amount
    ) public view returns (bool) {
        uint256 currentRatio = getCollateralizationRatio(user);
        if (currentRatio == type(uint256).max) return true;

        // Calculate new ratio after withdrawal
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address supportedToken = supportedTokens[i];
            if (markets[supportedToken].isActive) {
                uint256 depositAmount = userDeposits[user][supportedToken];
                uint256 borrowAmount = userBorrows[user][supportedToken];

                if (supportedToken == token) {
                    depositAmount = depositAmount > amount
                        ? depositAmount - amount
                        : 0;
                }

                if (depositAmount > 0) {
                    totalCollateralValue +=
                        (depositAmount *
                            markets[supportedToken].collateralFactor) /
                        BASIS_POINTS;
                }

                if (borrowAmount > 0) {
                    totalBorrowValue += borrowAmount;
                }
            }
        }

        if (totalBorrowValue == 0) return true;
        uint256 newRatio = (totalCollateralValue * BASIS_POINTS) /
            totalBorrowValue;
        return newRatio >= LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Check if a user can borrow additional tokens
     * @param user The user address
     * @param token The token to borrow
     * @param amount The amount to borrow
     * @return True if borrow is allowed
     */
    function canBorrow(
        address user,
        address token,
        uint256 amount
    ) public view returns (bool) {
        uint256 currentRatio = getCollateralizationRatio(user);
        if (currentRatio == type(uint256).max) return true;

        // Calculate new ratio after borrow
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address supportedToken = supportedTokens[i];
            if (markets[supportedToken].isActive) {
                uint256 depositAmount = userDeposits[user][supportedToken];
                uint256 borrowAmount = userBorrows[user][supportedToken];

                if (supportedToken == token) {
                    borrowAmount += amount;
                }

                if (depositAmount > 0) {
                    totalCollateralValue +=
                        (depositAmount *
                            markets[supportedToken].collateralFactor) /
                        BASIS_POINTS;
                }

                if (borrowAmount > 0) {
                    totalBorrowValue += borrowAmount;
                }
            }
        }

        if (totalBorrowValue == 0) return true;
        uint256 newRatio = (totalCollateralValue * BASIS_POINTS) /
            totalBorrowValue;
        return newRatio >= LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Get user's current collateralization ratio
     * @param user The user address
     * @return ratio The collateralization ratio in basis points
     */
    function getCollateralizationRatio(
        address user
    ) public view returns (uint256 ratio) {
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address supportedToken = supportedTokens[i];
            if (markets[supportedToken].isActive) {
                uint256 depositAmount = userDeposits[user][supportedToken];
                uint256 borrowAmount = userBorrows[user][supportedToken];

                if (depositAmount > 0) {
                    totalCollateralValue +=
                        (depositAmount *
                            markets[supportedToken].collateralFactor) /
                        BASIS_POINTS;
                }

                if (borrowAmount > 0) {
                    totalBorrowValue += borrowAmount;
                }
            }
        }

        if (totalBorrowValue == 0) return type(uint256).max;
        return (totalCollateralValue * BASIS_POINTS) / totalBorrowValue;
    }

    /**
     * @dev Check if a user's position is liquidatable
     * @param user The user address
     * @return True if position can be liquidated
     */
    function isLiquidatable(address user) public view returns (bool) {
        uint256 ratio = getCollateralizationRatio(user);
        return ratio >= LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Find the best collateral token for liquidation
     * @param user The user address
     * @return The address of the best collateral token
     */
    function findBestCollateral(address user) internal view returns (address) {
        address bestToken = address(0);
        uint256 bestValue = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            if (markets[token].isActive && userDeposits[user][token] > 0) {
                uint256 value = (userDeposits[user][token] *
                    markets[token].collateralFactor) / BASIS_POINTS;
                if (value > bestValue) {
                    bestValue = value;
                    bestToken = token;
                }
            }
        }

        return bestToken;
    }

    /**
     * @dev Get user's nonce for signature verification
     * @param user The user address
     * @return The current nonce
     */
    function getNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }

    /**
     * @dev Get market information
     * @param token The token address
     * @return Market information
     */
    function getMarket(address token) external view returns (Market memory) {
        return markets[token];
    }

    /**
     * @dev Get user information
     * @param user The user address
     * @return User information
     */
    function getUser(address user) external view returns (User memory) {
        return users[user];
    }

    /**
     * @dev Get user's deposit for a specific token
     * @param user The user address
     * @param token The token address
     * @return The deposit amount
     */
    function getUserDeposit(
        address user,
        address token
    ) external view returns (uint256) {
        return userDeposits[user][token];
    }

    /**
     * @dev Get user's borrow for a specific token
     * @param user The user address
     * @param token The token address
     * @return The borrow amount
     */
    function getUserBorrow(
        address user,
        address token
    ) external view returns (uint256) {
        return userBorrows[user][token];
    }

    /**
     * @dev Get all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }
    /**
     * @dev Pause the protocol (emergency function)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the protocol
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
