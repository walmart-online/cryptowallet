// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title USDT Donation Contract (TRC-20 / TRON)
/// @notice Смарт-контракт для приёма донатов в USDT на сети TRON
/// @dev USDT TRC-20 адрес в mainnet: TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t

// ==================== ИНТЕРФЕЙС TRC-20 ====================
// Это описание функций токена USDT, которые нам нужны

interface ITRC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

// ==================== ОСНОВНОЙ КОНТРАКТ ====================

contract USDTDonation {

    // ==================== ПЕРЕМЕННЫЕ ====================

    /// @notice Владелец контракта
    address public owner;

    /// @notice Адрес токена USDT TRC-20
    /// Mainnet: TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
    /// Nile testnet: TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf
    ITRC20 public usdt;

    /// @notice Общая сумма донатов (в единицах USDT, 6 знаков после запятой)
    uint256 public totalDonations;

    /// @notice Количество донатов
    uint256 public donationCount;

    /// @notice Минимальный донат (1 USDT = 1_000_000, т.к. у USDT 6 decimals)
    uint256 public minDonation = 1_000_000; // 1 USDT

    /// @notice Сколько задонатил каждый адрес
    mapping(address => uint256) public donationsByAddress;

    /// @notice Структура доната
    struct Donation {
        address donor;       // Кто отправил
        uint256 amount;      // Сколько USDT (в wei, 6 decimals)
        uint256 timestamp;   // Когда
        string message;      // Сообщение
    }

    /// @notice Все донаты
    Donation[] public donations;

    // ==================== СОБЫТИЯ ====================

    event DonationReceived(
        address indexed donor,
        uint256 amount,
        string message,
        uint256 timestamp
    );

    event Withdrawal(address indexed owner, uint256 amount);
    event MinDonationChanged(uint256 oldMin, uint256 newMin);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // ==================== МОДИФИКАТОРЫ ====================

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ==================== КОНСТРУКТОР ====================

    /// @notice Создание контракта
    /// @param _usdtAddress Адрес токена USDT TRC-20
    constructor(address _usdtAddress) {
        require(_usdtAddress != address(0), "Invalid USDT address");
        owner = msg.sender;
        usdt = ITRC20(_usdtAddress);
    }

    // ==================== ОСНОВНЫЕ ФУНКЦИИ ====================

    /// @notice Отправить донат в USDT
    /// @param _amount Сумма в минимальных единицах (1 USDT = 1_000_000)
    /// @param _message Сообщение от донатера
    /// @dev Перед вызовом донатер должен сделать approve() на контракт USDT!
    function donate(uint256 _amount, string calldata _message) external {
        require(_amount >= minDonation, "Below minimum donation");

        // Проверяем что пользователь разрешил списание
        uint256 allowed = usdt.allowance(msg.sender, address(this));
        require(allowed >= _amount, "USDT allowance too low. Call approve() first");

        // Переводим USDT от донатера на этот контракт
        bool success = usdt.transferFrom(msg.sender, address(this), _amount);
        require(success, "USDT transfer failed");

        // Сохраняем донат
        donations.push(Donation({
            donor: msg.sender,
            amount: _amount,
            timestamp: block.timestamp,
            message: _message
        }));

        // Обновляем статистику
        donationsByAddress[msg.sender] += _amount;
        totalDonations += _amount;
        donationCount++;

        emit DonationReceived(msg.sender, _amount, _message, block.timestamp);
    }

    /// @notice Быстрый донат без сообщения
    /// @param _amount Сумма в минимальных единицах
    function quickDonate(uint256 _amount) external {
        require(_amount >= minDonation, "Below minimum donation");

        uint256 allowed = usdt.allowance(msg.sender, address(this));
        require(allowed >= _amount, "USDT allowance too low");

        bool success = usdt.transferFrom(msg.sender, address(this), _amount);
        require(success, "USDT transfer failed");

        donations.push(Donation({
            donor: msg.sender,
            amount: _amount,
            timestamp: block.timestamp,
            message: ""
        }));

        donationsByAddress[msg.sender] += _amount;
        totalDonations += _amount;
        donationCount++;

        emit DonationReceived(msg.sender, _amount, "", block.timestamp);
    }

    // ==================== ФУНКЦИИ ВЛАДЕЛЬЦА ====================

    /// @notice Вывести все USDT на кошелёк владельца
    function withdraw() external onlyOwner {
        uint256 balance = usdt.balanceOf(address(this));
        require(balance > 0, "No USDT to withdraw");

        bool success = usdt.transfer(owner, balance);
        require(success, "Withdrawal failed");

        emit Withdrawal(owner, balance);
    }

    /// @notice Вывести определённую сумму USDT
    /// @param _amount Сумма для вывода
    function withdrawAmount(uint256 _amount) external onlyOwner {
        uint256 balance = usdt.balanceOf(address(this));
        require(_amount <= balance, "Insufficient USDT balance");

        bool success = usdt.transfer(owner, _amount);
        require(success, "Withdrawal failed");

        emit Withdrawal(owner, _amount);
    }

    /// @notice Изменить минимальный донат
    /// @param _newMin Новый минимум (в единицах USDT с 6 decimals)
    function setMinDonation(uint256 _newMin) external onlyOwner {
        uint256 oldMin = minDonation;
        minDonation = _newMin;
        emit MinDonationChanged(oldMin, _newMin);
    }

    /// @notice Передать владение
    /// @param _newOwner Новый владелец
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    // ==================== ФУНКЦИИ ЧТЕНИЯ ====================

    /// @notice Баланс USDT на контракте
    function getBalance() external view returns (uint256) {
        return usdt.balanceOf(address(this));
    }

    /// @notice Баланс в человеко-читаемом формате (USDT с 6 decimals)
    function getBalanceUSDT() external view returns (uint256 whole, uint256 decimals_part) {
        uint256 balance = usdt.balanceOf(address(this));
        whole = balance / 1_000_000;
        decimals_part = balance % 1_000_000;
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

    /// @notice Общая сумма донатов от конкретного адреса
    function getDonationsByDonor(address _donor) external view returns (uint256) {
        return donationsByAddress[_donor];
    }

    /// @notice Проверить, достаточно ли у пользователя approve
    function checkAllowance(address _donor) external view returns (uint256) {
        return usdt.allowance(_donor, address(this));
    }
}
