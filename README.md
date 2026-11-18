# Agent Badge

A free soulbound badge for Agent ID holders, built for the **Agent ID Hackathon** (Binance Wallet × BNB Chain).

- **Free mint** (gas only), one badge per Agent ID holder. Minting is gated on holding an Agent ID: the contract checks `balanceOf` on the SPACE ID Agent ID registry (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`, BNB Smart Chain).
- **Daily check-in**: one check-in per UTC day grows an on-chain streak. Miss a day and the streak resets to 1.
- **Tiers by streak**: 0 — New Agent, 1–6 — Bronze, 7–29 — Silver, 30+ — Gold.
- **Soulbound**: the badge cannot be transferred. It is a permanent proof of consistent agent activity, bound to the agent.
- **Dynamic on-chain metadata**: `tokenURI` returns base64 JSON with an SVG badge that reflects the tier, token id and streak. No off-chain dependency.
- **No owner, no fees, no pause, no upgrades.** Fully permissionless.

## Contracts

| Item | Value |
|---|---|
| Network | BNB Smart Chain (chain 56) |
| Contract | `src/AgentBadge.sol` — ERC721 "Agent Badge" (`AGBADGE`), Solidity ^0.8.24, OpenZeppelin v5.7.0 |
| Deployed address | _TBD — fill in after deployment_ |
| Agent ID registry | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |

### Interface

```solidity
mint()                                    // free, one per Agent ID holder
checkIn()                                 // once per UTC day, grows the streak
badgeOf(address) view returns (uint256)
streakOf(uint256) view returns (uint256)
lastCheckInDayOf(uint256) view returns (uint256)
tierOf(uint256) view returns (uint8)      // 0 New Agent, 1 Bronze, 2 Silver, 3 Gold
totalBadges() view returns (uint256)
tokenURI(uint256) view returns (string)
```

Events: `BadgeMinted(address indexed holder, uint256 indexed tokenId)`, `CheckIn(uint256 indexed tokenId, uint256 indexed day, uint256 streak)`.

## Build & test

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0
forge test
```

19 tests, all passing. Note: do **not** enable `via_ir` — under Foundry 1.7.1 it miscompiles `block.timestamp` reads in this project.

## Website

Static site in `website/` (no backend, no build step). Preview locally:

```bash
cd website && python3 -m http.server 8931
# open http://127.0.0.1:8931/
```

Connect with an injected wallet (Binance Wallet / MetaMask) on BNB Smart Chain. Mint and check-in go through the user's own wallet confirmation — nothing is auto-signed, nothing extra is transferred. After deployment, set `contractAddress` in `website/config.js`.

## Disclaimer

Agent Badge is a free collectible with no financial value. It is not an investment and no returns of any kind are promised. Minting and check-ins only cost network gas.

## License

MIT — see [LICENSE](LICENSE).
