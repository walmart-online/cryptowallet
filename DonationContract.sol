// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title DonationContract - Смарт-контракт для приёма донатов
/// @notice Этот контракт позволяет принимать донаты в нативной валюте (ETH, MATIC, BNB и т.д.)
/// @dev Работает на любой EVM-совместимой сети

contract DonationContract {
    // ==================== ПЕРЕМЕННЫЕ ====================

    /// @notice Владелец контракта (тот, кто задеплоил)
    address public owner;

    /// @notice Общая сумма всех донатов
    uint256 public totalDonations;

    /// @notice Количество донатов
    uint256 public donationCount;

    /// @notice Маппинг: адрес донатера → сколько он задонатил всего
    mapping(address => uint256) public donationsByAddress;

    /// @notice Структура для хранения информации о донате
    struct Donation {
        address donor;      // Кто отправил
        uint256 amount;     // Сколько отправил
        uint256 timestamp;  // Когда отправил
        string message;     // Сообщение от донатера
    }

    /// @notice Массив всех донатов
    Donation[] public donations;

    // ==================== СОБЫТИЯ ====================

    /// @notice Событие при получении доната
    event DonationReceived(
        address indexed donor,
        uint256 amount,
        string message,
        uint256 timestamp
    );

    /// @notice Событие при выводе средств владельцем
    event Withdrawal(address indexed owner, uint256 amount);

    // ==================== МОДИФИКАТОРЫ ====================

    /// @notice Только владелец может вызвать функцию
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    // ==================== КОНСТРУКТОР ====================

    /// @notice Конструктор — вызывается один раз при деплое
    constructor() {
        owner = msg.sender; // Владелец = тот, кто задеплоил контракт
    }

    // ==================== ОСНОВНЫЕ ФУНКЦИИ ====================

    /// @notice Отправить донат с сообщением
    /// @param _message Сообщение от донатера
    function donate(string calldata _message) external payable {
        require(msg.value > 0, "Donation must be greater than 0");

        // Сохраняем донат
        donations.push(Donation({
            donor: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            message: _message
        }));

        // Обновляем статистику
        donationsByAddress[msg.sender] += msg.value;
        totalDonations += msg.value;
        donationCount++;

        // Генерируем событие
        emit DonationReceived(msg.sender, msg.value, _message, block.timestamp);
    }

    /// @notice Отправить донат без сообщения (просто отправить ETH на контракт)
    receive() external payable {
        require(msg.value > 0, "Donation must be greater than 0");

        donations.push(Donation({
            donor: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            message: ""
        }));

        donationsByAddress[msg.sender] += msg.value;
        totalDonations += msg.value;
        donationCount++;

        emit DonationReceived(msg.sender, msg.value, "", block.timestamp);
    }

    /// @notice Вывести все средства на кошелёк владельца
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(owner, balance);
    }

    /// @notice Вывести определённую сумму
    /// @param _amount Сумма для вывода в wei
    function withdrawAmount(uint256 _amount) external onlyOwner {
        require(_amount <= address(this).balance, "Insufficient balance");

        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(owner, _amount);
    }

    // ==================== ФУНКЦИИ ЧТЕНИЯ ====================

    /// @notice Баланс контракта
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Получить последние N донатов
    /// @param _count Сколько последних донатов вернуть
    function getRecentDonations(uint256 _count) external view returns (Donation[] memory) {
        uint256 count = _count > donations.length ? donations.length : _count;
        Donation[] memory recent = new Donation[](count);

        for (uint256 i = 0; i < count; i++) {
            recent[i] = donations[donations.length - count + i];
        }

        return recent;
    }

    /// @notice Сколько всего донатов сделал конкретный адрес
    /// @param _donor Адрес донатера
    function getDonationsByDonor(address _donor) external view returns (uint256) {
        return donationsByAddress[_donor];
    }

    /// @notice Передать владение контрактом другому адресу
    /// @param _newOwner Новый владелец
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        owner = _newOwner;
    }
}
