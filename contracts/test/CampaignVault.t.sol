// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignVault} from "../src/CampaignVault.sol";

contract CampaignVaultTest is Test {
    CampaignVault vault;

    address operator = makeAddr("operator");
    address brand = makeAddr("brand");
    address owner = makeAddr("owner"); // the human
    address petKey = makeAddr("petKey"); // the pet's own key
    address petWallet = makeAddr("petWallet");
    address stranger = makeAddr("stranger");

    uint96 constant RATE = 1e15; // 0.001 per impression
    uint256 constant BUDGET = 1 ether;
    bytes32 constant LINE = keccak256("Ship faster with Acme CI");

    function setUp() public {
        vault = new CampaignVault(operator);
        vm.deal(brand, 10 ether);
        vm.prank(operator);
        vault.registerPet(petKey, owner, petWallet);
    }

    function _create() internal returns (uint256 id) {
        vm.prank(brand);
        id = vault.createCampaign{value: BUDGET}(LINE, RATE, uint64(block.timestamp + 1 days));
    }

    function test_createLocksBudget() public {
        uint256 id = _create();
        assertEq(address(vault).balance, BUDGET);
        assertEq(vault.remaining(id), BUDGET);
    }

    function test_createRejectsBadParams() public {
        vm.startPrank(brand);
        vm.expectRevert(CampaignVault.BadParams.selector);
        vault.createCampaign{value: BUDGET}(LINE, 0, uint64(block.timestamp + 1));
        vm.expectRevert(CampaignVault.BadParams.selector);
        vault.createCampaign{value: BUDGET}(LINE, RATE, uint64(block.timestamp));
        vm.expectRevert(CampaignVault.BadParams.selector);
        vault.createCampaign{value: RATE - 1}(LINE, RATE, uint64(block.timestamp + 1));
        vm.stopPrank();
    }

    function test_settlePaysPetWallet() public {
        uint256 id = _create();
        vm.prank(operator);
        vault.settleImpressions(id, petKey, 100);
        assertEq(petWallet.balance, 100 * uint256(RATE));
        assertEq(vault.remaining(id), BUDGET - 100 * uint256(RATE));
    }

    function test_settleUpToExactBudget() public {
        uint256 id = _create();
        vm.prank(operator);
        vault.settleImpressions(id, petKey, BUDGET / RATE);
        assertEq(vault.remaining(id), 0);
    }

    function test_settleOverBudgetReverts() public {
        uint256 id = _create();
        vm.prank(operator);
        vm.expectRevert(CampaignVault.OverBudget.selector);
        vault.settleImpressions(id, petKey, BUDGET / RATE + 1);
    }

    function test_onlyOperatorSettles() public {
        uint256 id = _create();
        vm.prank(stranger);
        vm.expectRevert(CampaignVault.NotOperator.selector);
        vault.settleImpressions(id, petKey, 1);
    }

    function test_unverifiedPetReverts() public {
        uint256 id = _create();
        vm.prank(operator);
        vm.expectRevert(CampaignVault.PetNotVerified.selector);
        vault.settleImpressions(id, stranger, 1);

        vm.prank(operator);
        vault.setVerified(petKey, false);
        vm.prank(operator);
        vm.expectRevert(CampaignVault.PetNotVerified.selector);
        vault.settleImpressions(id, petKey, 1);
    }

    function test_petKeyCannotChangePayout() public {
        vm.prank(petKey);
        vm.expectRevert(CampaignVault.NotPetOwner.selector);
        vault.setPayout(petKey, stranger);

        vm.prank(operator);
        vm.expectRevert(CampaignVault.NotPetOwner.selector);
        vault.setPayout(petKey, stranger);
    }

    function test_ownerCanChangePayout() public {
        address newWallet = makeAddr("newWallet");
        vm.prank(owner);
        vault.setPayout(petKey, newWallet);
        uint256 id = _create();
        vm.prank(operator);
        vault.settleImpressions(id, petKey, 1);
        assertEq(newWallet.balance, RATE);
        assertEq(petWallet.balance, 0);
    }

    function test_cannotRegisterSamePetTwice() public {
        vm.prank(operator);
        vm.expectRevert(CampaignVault.BadParams.selector);
        vault.registerPet(petKey, stranger, stranger);
    }

    function test_refundAfterEnd() public {
        uint256 id = _create();
        vm.prank(operator);
        vault.settleImpressions(id, petKey, 200);
        uint256 before = brand.balance;
        vm.warp(block.timestamp + 1 days + vault.SETTLE_GRACE() + 1);
        vm.prank(stranger); // anyone can close
        vault.close(id);
        assertEq(brand.balance - before, BUDGET - 200 * uint256(RATE));
        assertEq(address(vault).balance, 0);
    }

    function test_closeBeforeEndReverts() public {
        uint256 id = _create();
        vm.expectRevert(CampaignVault.CampaignNotEnded.selector);
        vault.close(id);
    }

    function test_doubleCloseReverts() public {
        uint256 id = _create();
        vm.warp(block.timestamp + 1 days + vault.SETTLE_GRACE() + 1);
        vault.close(id);
        vm.expectRevert(CampaignVault.CampaignIsClosed.selector);
        vault.close(id);
    }

    function test_noSettleAfterClose() public {
        uint256 id = _create();
        vm.warp(block.timestamp + 1 days + vault.SETTLE_GRACE() + 1);
        vault.close(id);
        vm.prank(operator);
        vm.expectRevert(CampaignVault.CampaignIsClosed.selector);
        vault.settleImpressions(id, petKey, 1);
    }

    function test_topUpByBrandOnly() public {
        uint256 id = _create();
        vm.prank(brand);
        vault.topUp{value: 0.5 ether}(id);
        assertEq(vault.remaining(id), 1.5 ether);

        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(CampaignVault.NotBrand.selector);
        vault.topUp{value: 0.5 ether}(id);
    }

    function test_remainingIsZeroAfterClose() public {
        uint256 id = _create();
        vm.prank(operator);
        vault.settleImpressions(id, petKey, 10);
        vm.warp(block.timestamp + 1 days + vault.SETTLE_GRACE() + 1);
        vault.close(id);
        assertEq(vault.remaining(id), 0);
    }

    function test_settleWorksDuringGrace() public {
        uint256 id = _create();
        vm.warp(block.timestamp + 1 days + vault.SETTLE_GRACE()); // last second of grace
        vm.prank(operator);
        vault.settleImpressions(id, petKey, 5);
        assertEq(petWallet.balance, 5 * uint256(RATE));
    }

    function test_settleAfterGraceReverts() public {
        uint256 id = _create();
        vm.warp(block.timestamp + 1 days + vault.SETTLE_GRACE() + 1);
        vm.prank(operator);
        vm.expectRevert(CampaignVault.CampaignEnded.selector);
        vault.settleImpressions(id, petKey, 1);
    }

    function test_closeDuringGraceReverts() public {
        uint256 id = _create();
        vm.warp(block.timestamp + 1 days + 1); // past endTime, still inside grace
        vm.expectRevert(CampaignVault.CampaignNotEnded.selector);
        vault.close(id);
        vm.warp(block.timestamp + vault.SETTLE_GRACE()); // grace over
        vault.close(id);
    }

    function testFuzz_settleNeverExceedsBudget(uint256 a, uint256 b) public {
        uint256 id = _create();
        uint256 max = BUDGET / RATE;
        a = bound(a, 1, max);
        b = bound(b, 1, max);
        vm.startPrank(operator);
        vault.settleImpressions(id, petKey, a);
        if (a + b > max) {
            vm.expectRevert(CampaignVault.OverBudget.selector);
        }
        vault.settleImpressions(id, petKey, b);
        vm.stopPrank();
        assertLe(petWallet.balance, BUDGET);
        assertEq(petWallet.balance + vault.remaining(id), BUDGET);
    }

    // ---------- v2 ----------

    function test_pauseStopsMoneyInAndPayoutsButNotRefunds() public {
        uint256 id = _create();
        vm.prank(stranger);
        vm.expectRevert(CampaignVault.NotAdmin.selector);
        vault.setPaused(true);
        vault.setPaused(true); // the test contract deployed the vault, so it is admin
        vm.prank(brand);
        vm.expectRevert(CampaignVault.IsPaused.selector);
        vault.createCampaign{value: BUDGET}(LINE, RATE, uint64(block.timestamp + 1 days));
        vm.prank(operator);
        vm.expectRevert(CampaignVault.IsPaused.selector);
        vault.settleImpressions(id, petKey, 1);
        vm.prank(owner);
        vault.setPayout(petKey, owner); // owners can still move their payout
        vm.warp(block.timestamp + 1 days + 1 hours + 1);
        uint256 before = brand.balance;
        vault.close(id); // refunds never blocked
        assertEq(brand.balance, before + BUDGET);
    }

    function test_adminHandoverIsTwoStep() public {
        address safe = makeAddr("safe");
        vault.proposeAdmin(safe);
        assertEq(vault.admin(), address(this));
        vm.prank(stranger);
        vm.expectRevert(CampaignVault.NotAdmin.selector);
        vault.acceptAdmin();
        vm.prank(safe);
        vault.acceptAdmin();
        assertEq(vault.admin(), safe);
        vm.expectRevert(CampaignVault.NotAdmin.selector);
        vault.setPaused(true);
    }

    function test_settleBatchPaysEveryPet() public {
        address pet2 = makeAddr("pet2");
        address wallet2 = makeAddr("wallet2");
        vm.prank(operator);
        vault.registerPet(pet2, owner, wallet2);
        uint256 id = _create();
        address[] memory ps = new address[](2);
        uint256[] memory cs = new uint256[](2);
        (ps[0], ps[1], cs[0], cs[1]) = (petKey, pet2, 3, 7);
        vm.prank(operator);
        vault.settleBatch(id, ps, cs);
        assertEq(petWallet.balance, 3 * uint256(RATE));
        assertEq(wallet2.balance, 7 * uint256(RATE));
        assertEq(vault.remaining(id), BUDGET - 10 * uint256(RATE));
    }

    function test_settleBatchRevertsWhole() public {
        uint256 id = _create();
        address[] memory ps = new address[](2);
        uint256[] memory cs = new uint256[](2);
        (ps[0], ps[1], cs[0], cs[1]) = (petKey, stranger, 3, 7); // stranger is not a verified pet
        vm.prank(operator);
        vm.expectRevert(CampaignVault.PetNotVerified.selector);
        vault.settleBatch(id, ps, cs);
        assertEq(petWallet.balance, 0);
        vm.prank(operator);
        vm.expectRevert(CampaignVault.BadParams.selector);
        vault.settleBatch(id, ps, new uint256[](1));
        (ps[1], cs[0], cs[1]) = (petKey, BUDGET / RATE, 1); // together over budget
        vm.prank(operator);
        vm.expectRevert(CampaignVault.OverBudget.selector);
        vault.settleBatch(id, ps, cs);
    }
}

/// Random creates, top-ups, settles and closes; the vault must always hold exactly what campaigns have left.
contract VaultHandler is Test {
    CampaignVault public vault;
    address operator = makeAddr("operator");
    address pet = makeAddr("pet");
    uint256[] public ids;

    constructor(CampaignVault v) {
        vault = v;
        vm.prank(operator);
        vault.registerPet(pet, makeAddr("owner"), makeAddr("wallet"));
    }

    function create(uint96 rate, uint256 budget) external {
        rate = uint96(bound(rate, 1, 1e18));
        budget = bound(budget, rate, 100 ether);
        vm.deal(address(this), budget);
        ids.push(vault.createCampaign{value: budget}(bytes32(0), rate, uint64(block.timestamp + 1 days)));
    }

    function topUp(uint256 i, uint256 amount) external {
        if (ids.length == 0) return;
        amount = bound(amount, 1, 10 ether);
        vm.deal(address(this), amount);
        try vault.topUp{value: amount}(ids[i % ids.length]) {} catch {}
    }

    function settle(uint256 i, uint256 count) external {
        if (ids.length == 0) return;
        count = bound(count, 1, 1000);
        vm.prank(operator);
        try vault.settleImpressions(ids[i % ids.length], pet, count) {} catch {}
    }

    function close(uint256 i, uint256 dt) external {
        if (ids.length == 0) return;
        vm.warp(block.timestamp + bound(dt, 0, 3 days));
        try vault.close(ids[i % ids.length]) {} catch {}
    }

    function count() external view returns (uint256) {
        return ids.length;
    }

    receive() external payable {}
}

contract CampaignVaultInvariant is Test {
    CampaignVault vault;
    VaultHandler handler;

    function setUp() public {
        vault = new CampaignVault(makeAddr("operator"));
        handler = new VaultHandler(vault);
        targetContract(address(handler));
    }

    function invariant_balanceEqualsRemaining() public view {
        uint256 sum;
        for (uint256 i; i < handler.count(); ++i) {
            uint256 id = handler.ids(i);
            sum += vault.remaining(id);
            (, uint128 budget, uint128 spent,,,,) = vault.campaigns(id);
            assertLe(spent, budget);
        }
        assertEq(address(vault).balance, sum);
    }
}
