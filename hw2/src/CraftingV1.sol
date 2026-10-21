// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title CraftingV1 — мастерская игровых предметов (ERC-1155, первая версия)
/// @notice Дерево (id=1) и руда (id=2) выпускаются владельцем игры через issue,
///         мечи (id=3) — только крафтом: 3 дерева + 2 руды = 1 меч.
contract CraftingV1 is Initializable, ERC1155Upgradeable, OwnableUpgradeable {
    uint256 public constant WOOD = 1;
    uint256 public constant ORE = 2;
    uint256 public constant SWORD = 3;

    /// @notice Сколько мечей скрафчено за всю историю игры.
    uint256 public totalCrafted;

    event Crafted(address indexed player, uint256 amount);

    error ZeroAmount();
    error ZeroRecipient();
    error NotAResource(uint256 id);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Инициализация через прокси. Владелец игры задаётся один раз.
    function initialize(address owner_) public initializer {
        __ERC1155_init("");
        __Ownable_init(owner_);
    }

    /// @notice Выпуск ресурсов (только дерево и руда). Вызывает только владелец игры.
    function issue(address to, uint256 id, uint256 amount) external onlyOwner {
        if (id != WOOD && id != ORE) revert NotAResource(id);
        if (to == address(0)) revert ZeroRecipient();
        if (amount == 0) revert ZeroAmount();
        _mint(to, id, amount, "");
    }

    /// @notice Крафт n мечей: сжигает 3*n дерева и 2*n руды у вызывающего.
    ///         Сначала списания и счётчик, затем выпуск и вызов получателя —
    ///         отказ получателя откатывает операцию целиком.
    function craft(uint256 n) external {
        if (n == 0) revert ZeroAmount();
        _burn(msg.sender, WOOD, 3 * n);
        _burn(msg.sender, ORE, 2 * n);
        totalCrafted += n;
        emit Crafted(msg.sender, n);
        _mint(msg.sender, SWORD, n, "");
    }
}
