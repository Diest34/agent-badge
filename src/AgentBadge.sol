// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Agent Badge
/// @notice A free soulbound badge for Agent ID holders. One badge per holder.
/// Daily check-ins build an on-chain streak that sets the badge tier.
/// No fees, no owner, no admin, no upgrades: fully permissionless.
interface IAgentIdRegistry {
    function balanceOf(address account) external view returns (uint256);
}

contract AgentBadge is ERC721 {
    using Strings for uint256;

    IAgentIdRegistry public immutable agentIdRegistry;

    uint256 public nextTokenId = 1;

    mapping(address => uint256) public badgeOf;
    mapping(uint256 => uint256) public streak;
    mapping(uint256 => uint256) public lastCheckInDay;

    event BadgeMinted(address indexed holder, uint256 indexed tokenId);
    event CheckIn(uint256 indexed tokenId, uint256 indexed day, uint256 streak);

    constructor(address registry_) ERC721("Agent Badge", "AGBADGE") {
        require(registry_ != address(0), "ZERO_REGISTRY");
        agentIdRegistry = IAgentIdRegistry(registry_);
    }

    /// @notice Mint one free badge. Caller must hold an Agent ID and not
    /// already own a badge.
    function mint() external {
        require(agentIdRegistry.balanceOf(msg.sender) > 0, "NOT_AGENT_ID_HOLDER");
        require(badgeOf[msg.sender] == 0, "ALREADY_MINTED");
        uint256 tokenId = nextTokenId++;
        badgeOf[msg.sender] = tokenId;
        _mint(msg.sender, tokenId);
        emit BadgeMinted(msg.sender, tokenId);
    }

    /// @notice Check in once per UTC day. Consecutive days grow the streak;
    /// a missed day resets it to 1.
    function checkIn() external {
        uint256 tokenId = badgeOf[msg.sender];
        require(tokenId != 0, "NO_BADGE");
        uint256 day = block.timestamp / 1 days;
        require(day > lastCheckInDay[tokenId], "ALREADY_CHECKED_IN_TODAY");
        if (day == lastCheckInDay[tokenId] + 1) {
            streak[tokenId] += 1;
        } else {
            streak[tokenId] = 1;
        }
        lastCheckInDay[tokenId] = day;
        emit CheckIn(tokenId, day, streak[tokenId]);
    }

    /// @notice Soulbound: only minting (from == address(0)) is allowed.
    /// Every transfer attempt reverts.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        require(from == address(0), "SOULBOUND");
        return super._update(to, tokenId, auth);
    }

    /// @notice Tier by streak: 0 = New Agent, 1-6 = Bronze, 7-29 = Silver,
    /// 30+ = Gold.
    function tierOf(uint256 tokenId) public view returns (uint8) {
        uint256 s = streak[tokenId];
        if (s >= 30) return 3;
        if (s >= 7) return 2;
        if (s >= 1) return 1;
        return 0;
    }

    function streakOf(uint256 tokenId) external view returns (uint256) {
        return streak[tokenId];
    }

    function lastCheckInDayOf(uint256 tokenId) external view returns (uint256) {
        return lastCheckInDay[tokenId];
    }

    function totalBadges() external view returns (uint256) {
        return nextTokenId - 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint8 tier = tierOf(tokenId);
        string memory svgB64 = Base64.encode(bytes(_svg(tokenId, tier)));
        string memory jsonB64 = Base64.encode(bytes(_json(tokenId, tier, svgB64)));
        return string(abi.encodePacked("data:application/json;base64,", jsonB64));
    }

    function _json(uint256 tokenId, uint8 tier, string memory svgB64) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                '{"name":"Agent Badge #',
                tokenId.toString(),
                '","description":"A soulbound badge for Agent ID holders. Minted free, levelled up by daily check-ins. No financial value.",',
                '"image":"data:image/svg+xml;base64,',
                svgB64,
                '","attributes":[',
                _attributes(tokenId, tier),
                "]}"
            )
        );
    }

    function _attributes(uint256 tokenId, uint8 tier) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                '{"trait_type":"Tier","value":"',
                _tierName(tier),
                '"},',
                '{"trait_type":"Streak","value":',
                streak[tokenId].toString(),
                '},',
                '{"trait_type":"Last check-in day","value":',
                lastCheckInDay[tokenId].toString(),
                '},',
                '{"trait_type":"Token ID","value":',
                tokenId.toString(),
                "}"
            )
        );
    }

    function _tierName(uint8 tier) internal pure returns (string memory) {
        if (tier == 3) return "Gold";
        if (tier == 2) return "Silver";
        if (tier == 1) return "Bronze";
        return "New Agent";
    }

    function _tierColor(uint8 tier) internal pure returns (string memory) {
        if (tier == 3) return "#ffd700";
        if (tier == 2) return "#c0c0c0";
        if (tier == 1) return "#cd7f32";
        return "#9aa0a6";
    }

    function _svg(uint256 tokenId, uint8 tier) internal view returns (string memory) {
        string memory color = _tierColor(tier);
        string memory head = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">',
                '<rect width="400" height="400" fill="#0b0e1a"/>',
                '<rect x="16" y="16" width="368" height="368" rx="24" fill="',
                color,
                '" fill-opacity="0.16" stroke="',
                color,
                '" stroke-width="3"/>',
                '<text x="200" y="110" font-family="sans-serif" font-size="30" font-weight="bold" fill="#ffffff" text-anchor="middle">AGENT BADGE</text>'
            )
        );
        uint256 s = streak[tokenId];
        string memory body = string(
            abi.encodePacked(
                '<text x="200" y="165" font-family="sans-serif" font-size="22" fill="#ffffff" text-anchor="middle">Badge #',
                tokenId.toString(),
                "</text>",
                '<text x="200" y="215" font-family="sans-serif" font-size="24" font-weight="bold" fill="',
                color,
                '" text-anchor="middle">',
                _tierName(tier),
                "</text>",
                '<text x="200" y="265" font-family="sans-serif" font-size="20" fill="#ffffff" text-anchor="middle">Streak: ',
                s.toString(),
                s == 1 ? " day" : " days",
                "</text>"
            )
        );
        return string(
            abi.encodePacked(
                head,
                body,
                '<text x="200" y="310" font-family="sans-serif" font-size="15" fill="#9aa0a6" text-anchor="middle">Soulbound - one per Agent ID holder</text>',
                "</svg>"
            )
        );
    }
}
