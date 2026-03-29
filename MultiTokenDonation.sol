// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MultiTokenDonation — Мультитокен контракт для донатов
/// @notice Принимает донаты в нативной валюте (ETH/BNB/MATIC/AVAX и т.д.)
///         и в любых ERC-20/BEP-20 токенах (USDT, USDC, DAI, WBTC, SHIB и др.)
/// @dev Один контракт — деплоится на любую EVM-сеть

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

contract MultiTokenDonation {

    // ==================== ПЕРЕМЕННЫЕ ====================

    address public owner;

    /// @notice Общее кол-во донатов
    uint256 public donationCount;

    /// @notice Список поддерживаемых токенов (адреса)
    address[] public supportedTokens;

    /// @notice Токен поддерживается? (адрес → true/false)
    mapping(address => bool) public isTokenSupported;

    /// @notice Общая сумма донатов по каждому токену
    mapping(address => uint256) public totalByToken;

    /// @notice Сумма донатов в нативной валюте (ETH/BNB/MATIC)
    uint256 public totalNativeDonations;

    /// @notice Адрес 0x0 используется для нативной валюты
    address public constant NATIVE = address(0);

    struct Donation {
        address donor;
        address token;       // address(0) = нативная валюта
        uint256 amount;
        uint256 timestamp;
        string message;
    }

    Donation[] public donations;

    /// @notice Сколько донатил каждый адрес (в каждом токене)
    mapping(address => mapping(address => uint256)) public donorTotalByToken;

    // ==================== СОБЫТИЯ ====================

    event DonationReceived(
        address indexed donor,
        address indexed token,
        uint256 amount,
        string message,
        uint256 timestamp
    );

    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);
    event Withdrawal(address indexed token, uint256 amount);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // ==================== МОДИФИКАТОРЫ ====================

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ==================== КОНСТРУКТОР ====================

    /// @notice При деплое можно сразу указать список токенов
    /// @param _tokens Массив адресов ERC-20 токенов для поддержки
    constructor(address[] memory _tokens) {
        owner = msg.sender;

        // Добавляем указанные токены
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] != address(0) && !isTokenSupported[_tokens[i]]) {
                supportedTokens.push(_tokens[i]);
                isTokenSupported[_tokens[i]] = true;
            }
        }
    }

    // ==================== ДОНАТЫ В НАТИВНОЙ ВАЛЮТЕ ====================

    /// @notice Донат в нативной валюте (ETH, BNB, MATIC, AVAX...)
    /// @param _message Сообщение
    function donateNative(string calldata _message) external payable {
        require(msg.value > 0, "Amount must be > 0");

        donations.push(Donation({
            donor: msg.sender,
            token: NATIVE,
            amount: msg.value,
            timestamp: block.timestamp,
            message: _message
        }));

        donorTotalByToken[msg.sender][NATIVE] += msg.value;
        totalNativeDonations += msg.value;
        donationCount++;

        emit DonationReceived(msg.sender, NATIVE, msg.value, _message, block.timestamp);
    }

    /// @notice Просто отправить ETH/BNB на контракт
    receive() external payable {
        donations.push(Donation({
            donor: msg.sender,
            token: NATIVE,
            amount: msg.value,
            timestamp: block.timestamp,
            message: ""
        }));

        donorTotalByToken[msg.sender][NATIVE] += msg.value;
        totalNativeDonations += msg.value;
        donationCount++;

        emit DonationReceived(msg.sender, NATIVE, msg.value, "", block.timestamp);
    }

    // ==================== ДОНАТЫ В ERC-20 ТОКЕНАХ ====================

    /// @notice Донат в любом поддерживаемом ERC-20 токене
    /// @param _token Адрес токена (USDT, USDC, DAI и т.д.)
    /// @param _amount Сумма (с учётом decimals токена)
    /// @param _message Сообщение
    /// @dev Донатер должен сначала сделать approve()!
    function donateToken(
        address _token,
        uint256 _amount,
        string calldata _message
    ) external {
        require(isTokenSupported[_token], "Token not supported");
        require(_amount > 0, "Amount must be > 0");

        IERC20 token = IERC20(_token);

        uint256 allowed = token.allowance(msg.sender, address(this));
        require(allowed >= _amount, "Allowance too low. Call approve() first");

        bool success = token.transferFrom(msg.sender, address(this), _amount);
        require(success, "Transfer failed");

        donations.push(Donation({
            donor: msg.sender,
            token: _token,
            amount: _amount,
            timestamp: block.timestamp,
            message: _message
        }));

        donorTotalByToken[msg.sender][_token] += _amount;
        totalByToken[_token] += _amount;
        donationCount++;

        emit DonationReceived(msg.sender, _token, _amount, _message, block.timestamp);
    }

    // ==================== УПРАВЛЕНИЕ ТОКЕНАМИ ====================

    /// @notice Добавить поддерживаемый токен
    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        require(!isTokenSupported[_token], "Already supported");

        supportedTokens.push(_token);
        isTokenSupported[_token] = true;

        // Пытаемся получить symbol для события
        try IERC20(_token).symbol() returns (string memory sym) {
            emit TokenAdded(_token, sym);
        } catch {
            emit TokenAdded(_token, "UNKNOWN");
        }
    }

    /// @notice Убрать токен из поддерживаемых
    function removeToken(address _token) external onlyOwner {
        require(isTokenSupported[_token], "Not supported");
        isTokenSupported[_token] = false;

        // Удаляем из массива
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == _token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(_token);
    }

    // ==================== ВЫВОД СРЕДСТВ ====================

    /// @notice Вывести нативную валюту
    function withdrawNative() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No native balance");

        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(NATIVE, balance);
    }

    /// @notice Вывести конкретный ERC-20 токен
    function withdrawToken(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No token balance");

        bool success = token.transfer(owner, balance);
        require(success, "Withdrawal failed");

        emit Withdrawal(_token, balance);
    }

    /// @notice Вывести ВСЕ токены + нативную валюту
    function withdrawAll() external onlyOwner {
        // Нативная валюта
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance > 0) {
            (bool success, ) = payable(owner).call{value: nativeBalance}("");
            require(success, "Native withdrawal failed");
            emit Withdrawal(NATIVE, nativeBalance);
        }

        // Все ERC-20 токены
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address tokenAddr = supportedTokens[i];
            IERC20 token = IERC20(tokenAddr);
            uint256 balance = token.balanceOf(address(this));

            if (balance > 0) {
                bool success = token.transfer(owner, balance);
                if (success) {
                    emit Withdrawal(tokenAddr, balance);
                }
            }
        }
    }

    // ==================== ФУНКЦИИ ЧТЕНИЯ ====================

    /// @notice Список всех поддерживаемых токенов
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /// @notice Баланс нативной валюты на контракте
    function getNativeBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Баланс конкретного токена на контракте
    function getTokenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /// @notice Последние N донатов
    function getRecentDonations(uint256 _count) external view returns (Donation[] memory) {
        uint256 count = _count > donations.length ? donations.length : _count;
        Donation[] memory recent = new Donation[](count);

        for (uint256 i = 0; i < count; i++) {
            recent[i] = donations[donations.length - count + i];
        }
        return recent;
    }

    /// @notice Проверить allowance пользователя для токена
    function checkAllowance(address _donor, address _token) external view returns (uint256) {
        return IERC20(_token).allowance(_donor, address(this));
    }

    /// @notice Передать владение
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        address old = owner;
        owner = _newOwner;
        emit OwnershipTransferred(old, _newOwner);
    }
}
