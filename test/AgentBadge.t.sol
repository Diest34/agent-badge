// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentBadge} from "../src/AgentBadge.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Minimal ERC721 used ONLY as a stand-in for the Agent ID registry
/// in tests. Never part of the deployment.
contract MockAgentID is ERC721 {
    uint256 public nextId = 1;

    constructor() ERC721("Mock Agent ID", "MAID") {}

    function mint(address to) external returns (uint256) {
        uint256 id = nextId++;
        _mint(to, id);
        return id;
    }
}

contract AgentBadgeTest is Test {
    MockAgentID internal registry;
    AgentBadge internal badge;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA901);

    // Fixed start time so `day` is a realistic day number, not day 0.
    uint256 internal constant T0 = 1_763_000_000; // ~2026-11-17

    event BadgeMinted(address indexed holder, uint256 indexed tokenId);
    event CheckIn(uint256 indexed tokenId, uint256 indexed day, uint256 streak);

    function setUp() public {
        vm.warp(T0);
        registry = new MockAgentID();
        badge = new AgentBadge(address(registry));
        registry.mint(alice);
        registry.mint(carol);
    }

    function _day() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function _mintAs(address who) internal returns (uint256) {
        vm.prank(who);
        badge.mint();
        return badge.badgeOf(who);
    }

    // ---- mint ----

    function testMintRevertsWithoutAgentId() public {
        vm.prank(bob);
        vm.expectRevert("NOT_AGENT_ID_HOLDER");
        badge.mint();
    }

    function testMintSucceedsWithAgentId() public {
        vm.expectEmit(true, true, false, true, address(badge));
        emit BadgeMinted(alice, 1);
        vm.prank(alice);
        badge.mint();

        assertEq(badge.badgeOf(alice), 1);
        assertEq(badge.balanceOf(alice), 1);
        assertEq(badge.ownerOf(1), alice);
        assertEq(badge.totalBadges(), 1);
        assertEq(badge.streakOf(1), 0);
        assertEq(badge.lastCheckInDayOf(1), 0);
        assertEq(badge.tierOf(1), 0);
        assertEq(badge.nextTokenId(), 2);
    }

    function testSecondMintReverts() public {
        _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert("ALREADY_MINTED");
        badge.mint();
    }

    function testTwoHoldersGetDifferentTokenIds() public {
        uint256 a = _mintAs(alice);
        uint256 c = _mintAs(carol);
        assertEq(a, 1);
        assertEq(c, 2);
        assertEq(badge.totalBadges(), 2);
    }

    // ---- checkIn ----

    function testCheckInRevertsWithoutBadge() public {
        vm.prank(bob);
        vm.expectRevert("NO_BADGE");
        badge.checkIn();
    }

    function testCheckInSameDayReverts() public {
        _mintAs(alice);
        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 1);
        assertEq(badge.lastCheckInDayOf(1), _day());

        vm.prank(alice);
        vm.expectRevert("ALREADY_CHECKED_IN_TODAY");
        badge.checkIn();
    }

    function testConsecutiveDaysIncrementStreak() public {
        _mintAs(alice);
        uint256 day0 = _day();

        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 1);

        vm.warp(block.timestamp + 1 days);
        uint256 day1 = _day();
        assertEq(day1, day0 + 1);
        vm.expectEmit(true, true, false, true, address(badge));
        emit CheckIn(1, day1, 2);
        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 2);
        assertEq(badge.lastCheckInDayOf(1), day1);

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 3);
        assertEq(badge.lastCheckInDayOf(1), day0 + 2);
    }

    function testMissedDayResetsStreakToOne() public {
        _mintAs(alice);
        vm.prank(alice);
        badge.checkIn(); // streak 1
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        badge.checkIn(); // streak 2
        assertEq(badge.streakOf(1), 2);

        vm.warp(block.timestamp + 2 days); // skip one whole day
        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 1);
    }

    function testCheckInAfterLongGapResetsStreak() public {
        _mintAs(alice);
        vm.prank(alice);
        badge.checkIn();
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 2);

        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        badge.checkIn();
        assertEq(badge.streakOf(1), 1);
    }

    // ---- soulbound ----

    function testTransferRevertsSoulbound() public {
        _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert("SOULBOUND");
        badge.transferFrom(alice, bob, 1);
    }

    function testSafeTransferRevertsSoulbound() public {
        _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert("SOULBOUND");
        badge.safeTransferFrom(alice, bob, 1);
    }

    function testApprovedTransferRevertsSoulbound() public {
        _mintAs(alice);
        vm.prank(alice);
        badge.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert("SOULBOUND");
        badge.transferFrom(alice, bob, 1);
    }

    // ---- tiers ----

    function _checkInDays(uint256 n) internal {
        // Warps +1 day before every check-in, so each lands on a fresh day.
        for (uint256 i = 0; i < n; i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(alice);
            badge.checkIn();
        }
    }

    function testTierTransitions() public {
        _mintAs(alice);
        assertEq(badge.tierOf(1), 0, "streak 0 -> tier 0");

        _checkInDays(1);
        assertEq(badge.streakOf(1), 1);
        assertEq(badge.tierOf(1), 1, "streak 1 -> tier 1 Bronze");

        _checkInDays(5); // streak 6
        assertEq(badge.streakOf(1), 6);
        assertEq(badge.tierOf(1), 1, "streak 6 -> still tier 1");

        _checkInDays(1); // streak 7
        assertEq(badge.streakOf(1), 7);
        assertEq(badge.tierOf(1), 2, "streak 7 -> tier 2 Silver");

        _checkInDays(22); // streak 29
        assertEq(badge.streakOf(1), 29);
        assertEq(badge.tierOf(1), 2, "streak 29 -> still tier 2");

        _checkInDays(1); // streak 30
        assertEq(badge.streakOf(1), 30);
        assertEq(badge.tierOf(1), 3, "streak 30 -> tier 3 Gold");

        _checkInDays(5); // streak 35
        assertEq(badge.streakOf(1), 35);
        assertEq(badge.tierOf(1), 3, "streak 35 -> still tier 3");
    }

    // ---- tokenURI ----

    function testTokenUriDecodesToValidJson() public {
        _mintAs(alice);
        _checkInDays(3); // streak 3, tier Bronze
        uint256 day = _day();

        string memory uri = badge.tokenURI(1);
        assertTrue(_startsWith(uri, "data:application/json;base64,"), "uri prefix");

        string memory json = string(_b64decode(_after(uri, "data:application/json;base64,")));

        assertEq(vm.parseJsonString(json, ".name"), "Agent Badge #1");
        assertEq(
            vm.parseJsonString(json, ".description"),
            "A soulbound badge for Agent ID holders. Minted free, levelled up by daily check-ins. No financial value."
        );

        string memory image = vm.parseJsonString(json, ".image");
        assertTrue(_startsWith(image, "data:image/svg+xml;base64,"), "image prefix");
        string memory svg = string(_b64decode(_after(image, "data:image/svg+xml;base64,")));
        assertTrue(_contains(svg, "AGENT BADGE"), "svg title");
        assertTrue(_contains(svg, "Badge #1"), "svg token id");
        assertTrue(_contains(svg, "Bronze"), "svg tier");
        assertTrue(_contains(svg, "Streak: 3 days"), "svg streak");

        assertTrue(_contains(json, '"trait_type":"Tier","value":"Bronze"'), "attr tier");
        assertTrue(_contains(json, '"trait_type":"Streak","value":3'), "attr streak");
        assertTrue(_contains(json, '"trait_type":"Token ID","value":1'), "attr token id");
        string memory dayAttr = string.concat('"trait_type":"Last check-in day","value":', vm.toString(day));
        assertTrue(_contains(json, dayAttr), "attr last check-in day");
    }

    function testTokenUriTierNameFollowsStreak() public {
        _mintAs(alice);
        _checkInDays(7); // streak 7 -> Silver
        string memory json = string(
            _b64decode(_after(badge.tokenURI(1), "data:application/json;base64,"))
        );
        assertTrue(_contains(json, '"trait_type":"Tier","value":"Silver"'), "silver at 7");

        _checkInDays(23); // streak 30 -> Gold
        json = string(_b64decode(_after(badge.tokenURI(1), "data:application/json;base64,")));
        assertTrue(_contains(json, '"trait_type":"Tier","value":"Gold"'), "gold at 30");
        assertTrue(_contains(json, '"trait_type":"Streak","value":30'), "streak 30");
    }

    function testTokenUriRevertsForNonexistentToken() public {
        vm.expectRevert();
        badge.tokenURI(999);
    }

    // ---- gas reporting ----

    function testGasMint() public {
        uint256 before = gasleft();
        vm.prank(alice);
        badge.mint();
        emit log_named_uint("mint() gas", before - gasleft());
    }

    function testGasCheckInFirst() public {
        _mintAs(alice);
        uint256 before = gasleft();
        vm.prank(alice);
        badge.checkIn();
        emit log_named_uint("checkIn() first gas", before - gasleft());
    }

    function testGasCheckInRepeat() public {
        _mintAs(alice);
        vm.prank(alice);
        badge.checkIn();
        vm.warp(block.timestamp + 1 days);
        uint256 before = gasleft();
        vm.prank(alice);
        badge.checkIn();
        emit log_named_uint("checkIn() repeat gas", before - gasleft());
    }

    // ---- helpers (test-only) ----

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        if (a.length < b.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0) return true;
        if (h.length < n.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function _after(string memory s, string memory marker) internal pure returns (string memory) {
        bytes memory a = bytes(s);
        bytes memory m = bytes(marker);
        require(a.length >= m.length, "marker longer than string");
        for (uint256 i = 0; i < m.length; i++) {
            require(a[i] == m[i], "marker mismatch");
        }
        bytes memory out = new bytes(a.length - m.length);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = a[m.length + i];
        }
        return string(out);
    }

    function _b64val(bytes1 c) internal pure returns (uint256) {
        if (c == "=") return 0;
        if (c >= "A" && c <= "Z") return uint8(c) - uint8(bytes1("A"));
        if (c >= "a" && c <= "z") return uint8(c) - uint8(bytes1("a")) + 26;
        if (c >= "0" && c <= "9") return uint8(c) - uint8(bytes1("0")) + 52;
        if (c == "+") return 62;
        if (c == "/") return 63;
        revert("bad base64 char");
    }

    function _b64decode(string memory input) internal pure returns (bytes memory) {
        bytes memory data = bytes(input);
        require(data.length % 4 == 0, "bad base64 length");
        uint256 pad;
        if (data.length >= 1 && data[data.length - 1] == "=") pad++;
        if (data.length >= 2 && data[data.length - 2] == "=") pad++;
        uint256 outLen = (data.length / 4) * 3 - pad;
        bytes memory out = new bytes(outLen);
        uint256 j;
        for (uint256 i = 0; i < data.length; i += 4) {
            uint256 n = (_b64val(data[i]) << 18) | (_b64val(data[i + 1]) << 12) | (_b64val(data[i + 2]) << 6)
                | _b64val(data[i + 3]);
            if (j < outLen) out[j++] = bytes1(uint8(n >> 16));
            if (j < outLen) out[j++] = bytes1(uint8(n >> 8));
            if (j < outLen) out[j++] = bytes1(uint8(n));
        }
        return out;
    }
}
