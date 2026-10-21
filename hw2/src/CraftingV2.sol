// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {CraftingV1} from "./CraftingV1.sol";

/// @title CraftingV2 — добавляет разбор мечей (salvage).
/// @notice Наследует V1, новая переменная totalSalvaged дописывается в конец
///         хранилища, поэтому лейаут совместим с V1 (проверяется OpenZeppelin Upgrades).
/// @custom:oz-upgrades-from CraftingV1
contract CraftingV2 is CraftingV1 {
    /// @notice Сколько мечей разобрано за всю историю игры (начинается с нуля).
    uint256 public totalSalvaged;

    event Salvaged(address indexed player, uint256 amount);

    /// @notice Разбор n мечей: сжигает n мечей у вызывающего и выдаёт ему n руды.
    ///         totalCrafted не уменьшается. Порядок — списание и счётчик до выпуска.
    function salvage(uint256 n) external {
        if (n == 0) revert ZeroAmount();
        _burn(msg.sender, SWORD, n);
        totalSalvaged += n;
        emit Salvaged(msg.sender, n);
        _mint(msg.sender, ORE, n, "");
    }
}
