/* Agent Badge — static configuration.
 * No backend, no API keys, no analytics.
 * Fill in contractAddress after the contract is deployed on BNB Smart Chain.
 */
window.AGENT_BADGE_CONFIG = {
  chainId: 56,
  chainIdHex: "0x38",
  chainName: "BNB Smart Chain",
  rpcUrl: "https://bsc-dataseed.bnbchain.org",
  explorerUrl: "https://bscscan.com",

  // TODO: replace with the deployed Agent Badge contract address.
  contractAddress: "0x0000000000000000000000000000000000000000",

  // Agent ID registry (SPACE ID Agent ID, ERC-721, non-transferable) on BSC.
  agentIdRegistry: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",

  // Tier names, indexed by tierOf(tokenId): 0 New Agent, 1 Bronze, 2 Silver, 3 Gold.
  tierNames: ["New Agent", "Bronze", "Silver", "Gold"]
};
