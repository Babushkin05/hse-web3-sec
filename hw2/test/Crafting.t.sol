// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {CraftingV1} from "../src/CraftingV1.sol";
import {CraftingV2} from "../src/CraftingV2.sol";

/// @notice Получатель, который умеет принимать/отклонять ERC-1155 и ходить в игру.
contract ToggleReceiver is IERC1155Receiver {
    bool public accepts = true;

    function setAccepts(bool value) external {
        accepts = value;
    }

    function doCraft(address game, uint256 n) external {
        CraftingV1(game).craft(n);
    }

    function doSalvage(address game, uint256 n) external {
        CraftingV2(game).salvage(n);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        view
        returns (bytes4)
    {
        require(accepts, "receiver rejected");
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        require(accepts, "receiver rejected");
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

contract CraftingTest is Test {
    // Локальные константы id предметов (геттеры контракта нельзя подставлять
    // аргументами рядом с prank/expectRevert — это лишние внешние вызовы).
    uint256 internal constant WOOD = 1;
    uint256 internal constant ORE = 2;
    uint256 internal constant SWORD = 3;

    // Владелец игры и владелец ProxyAdmin — разные адреса.
    address internal gameOwner = makeAddr("gameOwner");
    address internal proxyAdminOwner = makeAddr("proxyAdminOwner");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");
    address internal attacker = makeAddr("attacker");

    address internal proxy;
    CraftingV1 internal game; // все обращения — через прокси

    function setUp() public {
        proxy = Upgrades.deployTransparentProxy(
            "CraftingV1.sol:CraftingV1", proxyAdminOwner, abi.encodeCall(CraftingV1.initialize, (gameOwner))
        );
        game = CraftingV1(proxy);
    }

    function _upgradeToV2() internal returns (CraftingV2 game2) {
        Upgrades.upgradeProxy(proxy, "CraftingV2.sol:CraftingV2", "", proxyAdminOwner);
        game2 = CraftingV2(proxy);
    }

    function _issueTo(address to, uint256 wood, uint256 ore) internal {
        vm.startPrank(gameOwner);
        game.issue(to, WOOD, wood);
        game.issue(to, ORE, ore);
        vm.stopPrank();
    }

    // ---------- Деплой и инициализация ----------

    function test_DeployState() public view {
        assertEq(game.owner(), gameOwner);
        assertTrue(gameOwner != proxyAdminOwner, "owners must differ");
        assertEq(game.totalCrafted(), 0);
        assertEq(game.WOOD(), WOOD);
        assertEq(game.ORE(), ORE);
        assertEq(game.SWORD(), SWORD);
        assertTrue(Upgrades.getAdminAddress(proxy) != address(0));
        assertEq(ProxyAdmin(Upgrades.getAdminAddress(proxy)).owner(), proxyAdminOwner);
    }

    function test_ReinitializeProxyReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        game.initialize(attacker);
    }

    function test_DirectInitializeImplementationsReverts() public {
        CraftingV1 implV1 = CraftingV1(Upgrades.getImplementationAddress(proxy));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implV1.initialize(attacker);

        CraftingV2 implV2 = new CraftingV2();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implV2.initialize(attacker);
    }

    // ---------- issue ----------

    function test_IssueResources() public {
        _issueTo(alice, 10, 7);
        assertEq(game.balanceOf(alice, WOOD), 10);
        assertEq(game.balanceOf(alice, ORE), 7);
    }

    function test_IssueOnlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        game.issue(alice, WOOD, 1);
    }

    function test_IssueUnknownIdReverts() public {
        vm.prank(gameOwner);
        vm.expectRevert(abi.encodeWithSelector(CraftingV1.NotAResource.selector, 99));
        game.issue(alice, 99, 1);
    }

    function test_IssueSwordReverts() public {
        vm.prank(gameOwner);
        vm.expectRevert(abi.encodeWithSelector(CraftingV1.NotAResource.selector, SWORD));
        game.issue(alice, SWORD, 1);
    }

    function test_IssueZeroRecipientReverts() public {
        vm.prank(gameOwner);
        vm.expectRevert(CraftingV1.ZeroRecipient.selector);
        game.issue(address(0), WOOD, 1);
    }

    function test_IssueZeroAmountReverts() public {
        vm.prank(gameOwner);
        vm.expectRevert(CraftingV1.ZeroAmount.selector);
        game.issue(alice, WOOD, 0);
    }

    // ---------- craft ----------

    function test_CraftSuccess() public {
        _issueTo(alice, 6, 4);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, proxy);
        emit CraftingV1.Crafted(alice, 2);
        game.craft(2);

        assertEq(game.balanceOf(alice, WOOD), 0);
        assertEq(game.balanceOf(alice, ORE), 0);
        assertEq(game.balanceOf(alice, SWORD), 2);
        assertEq(game.totalCrafted(), 2);
    }

    function test_CraftZeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert(CraftingV1.ZeroAmount.selector);
        game.craft(0);
    }

    function test_CraftInsufficientWoodReverts() public {
        _issueTo(alice, 2, 100); // не хватает дерева

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 2, 3, WOOD)
        );
        game.craft(1);

        assertEq(game.balanceOf(alice, WOOD), 2);
        assertEq(game.balanceOf(alice, ORE), 100);
        assertEq(game.balanceOf(alice, SWORD), 0);
        assertEq(game.totalCrafted(), 0);
    }

    function test_CraftInsufficientOreReverts() public {
        _issueTo(alice, 100, 1); // не хватает руды

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 1, 2, ORE)
        );
        game.craft(1);

        assertEq(game.balanceOf(alice, WOOD), 100);
        assertEq(game.balanceOf(alice, ORE), 1);
        assertEq(game.balanceOf(alice, SWORD), 0);
        assertEq(game.totalCrafted(), 0);
    }

    // ---------- обычные переводы и операторы ----------

    function test_TransfersAndOperatorsWork() public {
        _issueTo(alice, 6, 4);

        vm.prank(alice);
        game.setApprovalForAll(operator, true);
        assertTrue(game.isApprovedForAll(alice, operator));

        vm.prank(operator);
        game.safeTransferFrom(alice, bob, WOOD, 3, "");
        assertEq(game.balanceOf(bob, WOOD), 3);
        assertEq(game.balanceOf(alice, WOOD), 3);
    }

    // ---------- единый сценарий: V1 -> обновление -> salvage ----------

    function test_UpgradeScenarioPreservesState() public {
        // V1: выпуск и крафт
        _issueTo(alice, 6, 4);
        vm.prank(alice);
        game.craft(2);
        assertEq(game.totalCrafted(), 2);

        // разрешение оператору
        vm.prank(alice);
        game.setApprovalForAll(operator, true);

        // чужой апгрейд запрещён: ни атакующий, ни владелец игры не владеют ProxyAdmin
        ProxyAdmin admin = ProxyAdmin(Upgrades.getAdminAddress(proxy));
        address rogueImpl = address(new CraftingV2());
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        admin.upgradeAndCall(ITransparentUpgradeableProxy(proxy), rogueImpl, "");
        vm.prank(gameOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, gameOwner));
        admin.upgradeAndCall(ITransparentUpgradeableProxy(proxy), rogueImpl, "");

        // обновление выполняет только владелец ProxyAdmin
        CraftingV2 game2 = _upgradeToV2();

        // сохранённые данные
        assertEq(address(game2), proxy, "proxy address changed");
        assertEq(game2.owner(), gameOwner, "game owner changed");
        assertEq(game2.balanceOf(alice, WOOD), 0);
        assertEq(game2.balanceOf(alice, ORE), 0);
        assertEq(game2.balanceOf(alice, SWORD), 2);
        assertTrue(game2.isApprovedForAll(alice, operator), "approval lost");
        assertEq(game2.totalCrafted(), 2, "totalCrafted lost");
        assertEq(game2.totalSalvaged(), 0, "totalSalvaged must start at zero");

        // повторная инициализация прокси запрещена и после обновления
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        game2.initialize(attacker);

        // перевод меча оператором новому держателю
        vm.prank(operator);
        game2.safeTransferFrom(alice, bob, SWORD, 1, "");
        assertEq(game2.balanceOf(bob, SWORD), 1);
        assertEq(game2.balanceOf(alice, SWORD), 1);

        // разбор новым держателем
        vm.prank(bob);
        vm.expectEmit(true, false, false, true, proxy);
        emit CraftingV2.Salvaged(bob, 1);
        game2.salvage(1);

        assertEq(game2.balanceOf(bob, SWORD), 0);
        assertEq(game2.balanceOf(bob, ORE), 1);
        assertEq(game2.totalSalvaged(), 1);
        assertEq(game2.totalCrafted(), 2, "salvage must not decrease totalCrafted");
    }

    // ---------- отказ получателя и разбор без мечей ----------

    function test_CraftRevertsWhenReceiverRejects() public {
        ToggleReceiver receiver = new ToggleReceiver();

        // получатель сначала принимает ресурсы
        _issueTo(address(receiver), 3, 2);
        assertEq(game.balanceOf(address(receiver), WOOD), 3);
        assertEq(game.balanceOf(address(receiver), ORE), 2);

        // затем отклоняет меч при крафте — всё откатывается
        receiver.setAccepts(false);
        vm.expectRevert("receiver rejected");
        receiver.doCraft(proxy, 1);

        assertEq(game.balanceOf(address(receiver), WOOD), 3);
        assertEq(game.balanceOf(address(receiver), ORE), 2);
        assertEq(game.balanceOf(address(receiver), SWORD), 0);
        assertEq(game.totalCrafted(), 0);
    }

    function test_SalvageWithoutSwordsReverts() public {
        CraftingV2 game2 = _upgradeToV2();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 0, 1, SWORD)
        );
        game2.salvage(1);

        assertEq(game2.totalSalvaged(), 0);
    }

    function test_SalvageZeroAmountReverts() public {
        CraftingV2 game2 = _upgradeToV2();

        vm.prank(alice);
        vm.expectRevert(CraftingV1.ZeroAmount.selector);
        game2.salvage(0);
    }

    // ---------- fuzz: craft + salvage ----------

    function testFuzz_CraftAndSalvage(uint256 n) public {
        n = bound(n, 1, 1000);
        address player = vm.addr(n); // новый игрок на каждый запуск

        CraftingV2 game2 = _upgradeToV2();

        vm.startPrank(gameOwner);
        game2.issue(player, WOOD, 3 * n);
        game2.issue(player, ORE, 2 * n);
        vm.stopPrank();

        vm.prank(player);
        game2.craft(n);
        vm.prank(player);
        game2.salvage(n);

        assertEq(game2.balanceOf(player, WOOD), 0);
        assertEq(game2.balanceOf(player, SWORD), 0);
        assertEq(game2.balanceOf(player, ORE), n, "only n ore must remain");
        assertEq(game2.totalCrafted(), n, "totalCrafted must grow by n");
        assertEq(game2.totalSalvaged(), n, "totalSalvaged must grow by n");
    }
}
