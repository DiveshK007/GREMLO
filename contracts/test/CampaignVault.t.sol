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
}
