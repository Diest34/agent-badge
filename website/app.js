"use strict";
/* Agent Badge — static frontend.
 * No backend, no analytics, no session storage on any server.
 * Every transaction goes through the user's own wallet confirmation.
 * Never auto-signs, never batches extra transfers, never handles seed phrases.
 */

const CONFIG = window.AGENT_BADGE_CONFIG;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const REGISTRY_ABI = [
  "function balanceOf(address owner) view returns (uint256)"
];

const $ = (id) => document.getElementById(id);

let badgeAbi = null;
let readProvider = null;
let readContract = null;      // read-only Agent Badge contract (public RPC)
let registryContract = null;  // read-only Agent ID registry (public RPC)
let browserProvider = null;   // ethers BrowserProvider, after wallet connect
let signer = null;
let account = null;
let onCorrectChain = false;

let state = {
  agentIdHeld: false,
  badgeId: 0n,          // 0 = no badge
  streak: 0n,
  tier: 0,
  lastCheckInDay: 0n,
  totalBadges: 0n
};

function isDeployed() {
  return !!CONFIG.contractAddress &&
    CONFIG.contractAddress.toLowerCase() !== ZERO_ADDRESS;
}

function utcDayNumber() {
  return Math.floor(Date.now() / 86400000);
}

function shortAddress(addr) {
  return addr.slice(0, 6) + "\u2026" + addr.slice(-4);
}

function explorerTxUrl(hash) {
  return CONFIG.explorerUrl + "/tx/" + hash;
}

function showBox(el, html, kind) {
  el.classList.remove("hidden", "error", "success");
  if (kind) el.classList.add(kind);
  el.innerHTML = html;
}

function hideBox(el) {
  el.classList.add("hidden");
  el.innerHTML = "";
}

function setNetPill(mode, label) {
  const pill = $("netPill");
  pill.classList.remove("ok", "wrong");
  if (mode) pill.classList.add(mode);
  $("netLabel").textContent = label;
}

/* ---------- read-only setup ---------- */

async function loadAbi() {
  const res = await fetch("abi.json");
  if (!res.ok) throw new Error("Could not load abi.json (HTTP " + res.status + ")");
  badgeAbi = await res.json();
}

function setupReadContracts() {
  readProvider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  registryContract = new ethers.Contract(CONFIG.agentIdRegistry, REGISTRY_ABI, readProvider);
  if (isDeployed()) {
    readContract = new ethers.Contract(CONFIG.contractAddress, badgeAbi, readProvider);
  }
}

async function refreshPublicStats() {
  if (!isDeployed()) {
    $("stTotal").textContent = "\u2014";
    return;
  }
  try {
    state.totalBadges = await readContract.totalBadges();
    $("stTotal").textContent = state.totalBadges.toString();
  } catch (e) {
    $("stTotal").textContent = "\u2014";
  }
}

/* ---------- wallet ---------- */

function hasProvider() {
  return typeof window.ethereum !== "undefined";
}

async function connectWallet() {
  if (typeof ethers === "undefined") {
    showBox($("connectMsg"), "Failed to load the ethers library from the CDN. Check your connection and reload the page.", "error");
    return;
  }
  if (!hasProvider()) {
    $("noProviderBox").classList.remove("hidden");
    return;
  }
  hideBox($("connectMsg"));
  $("noProviderBox").classList.add("hidden");
  try {
    browserProvider = new ethers.BrowserProvider(window.ethereum);
    const accounts = await browserProvider.send("eth_requestAccounts", []);
    if (!accounts || accounts.length === 0) {
      showBox($("connectMsg"), "No account selected. Please choose an account in your wallet and try again.", "error");
      return;
    }
    account = accounts[0];
    signer = await browserProvider.getSigner();
    await refreshChainState();
    await refreshStatus();
    wireProviderEvents();
  } catch (e) {
    if (e && e.code === 4001) {
      showBox($("connectMsg"), "Connection request rejected in your wallet. Nothing was signed.", "error");
    } else {
      showBox($("connectMsg"), "Could not connect: " + escapeHtml(e && e.message ? e.message : String(e)), "error");
    }
  }
}

async function refreshChainState() {
  const network = await browserProvider.getNetwork();
  onCorrectChain = Number(network.chainId) === CONFIG.chainId;
  if (onCorrectChain) {
    setNetPill("ok", CONFIG.chainName + " \u2022 Connected");
    $("switchBtn").classList.add("hidden");
  } else {
    setNetPill("wrong", "Wrong network \u2014 switch to " + CONFIG.chainName);
    $("switchBtn").classList.remove("hidden");
  }
}

async function switchToBsc() {
  hideBox($("connectMsg"));
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CONFIG.chainIdHex }]
    });
  } catch (e) {
    if (e && e.code === 4902) {
      // Chain not added in this wallet yet — add it, then switch.
      try {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: CONFIG.chainIdHex,
            chainName: CONFIG.chainName,
            nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
            rpcUrls: [CONFIG.rpcUrl],
            blockExplorerUrls: [CONFIG.explorerUrl]
          }]
        });
      } catch (addErr) {
        if (addErr && addErr.code === 4001) {
          showBox($("connectMsg"), "Adding BNB Smart Chain was rejected in your wallet.", "error");
        } else {
          showBox($("connectMsg"), "Could not add BNB Smart Chain: " + escapeHtml(addErr && addErr.message ? addErr.message : String(addErr)), "error");
        }
        return;
      }
    } else if (e && e.code === 4001) {
      showBox($("connectMsg"), "Network switch rejected in your wallet.", "error");
      return;
    } else {
      showBox($("connectMsg"), "Could not switch network: " + escapeHtml(e && e.message ? e.message : String(e)), "error");
      return;
    }
  }
  await refreshChainState();
  await refreshStatus();
}

let providerEventsWired = false;
function wireProviderEvents() {
  if (providerEventsWired || !window.ethereum || !window.ethereum.on) return;
  providerEventsWired = true;
  window.ethereum.on("accountsChanged", async (accounts) => {
    if (!accounts || accounts.length === 0) {
      account = null;
      signer = null;
      resetStatusPanel();
    } else {
      account = accounts[0];
      signer = await browserProvider.getSigner();
      await refreshStatus();
    }
  });
  window.ethereum.on("chainChanged", async () => {
    await refreshChainState();
    await refreshStatus();
  });
}

/* ---------- status ---------- */

function resetStatusPanel() {
  $("stAddress").textContent = "Not connected";
  $("stAddressSub").textContent = "";
  $("stAgentId").textContent = "\u2014";
  $("stAgentId").className = "value";
  $("stBadge").textContent = "\u2014";
  $("stBadgeSub").textContent = "";
  $("stStreak").textContent = "\u2014";
  $("stStreakSub").textContent = "Consecutive UTC days";
  $("stTier").textContent = "\u2014";
  $("stTierSub").textContent = "";
  $("badgeEmpty").classList.remove("hidden");
  $("badgeFilled").classList.add("hidden");
  updateActionButtons();
}

async function refreshStatus() {
  if (!account) {
    resetStatusPanel();
    return;
  }
  $("stAddress").textContent = shortAddress(account);
  $("stAddressSub").textContent = account;

  // Agent ID held? balanceOf on the registry, read-only.
  try {
    const bal = await registryContract.balanceOf(account);
    state.agentIdHeld = bal > 0n;
    const el = $("stAgentId");
    el.textContent = state.agentIdHeld ? "Yes" : "No";
    el.className = "value " + (state.agentIdHeld ? "yes" : "no");
  } catch (e) {
    state.agentIdHeld = false;
    $("stAgentId").textContent = "Error";
    $("stAgentId").className = "value";
  }

  if (!isDeployed()) {
    $("stBadge").textContent = "Contract not deployed yet";
    $("stBadgeSub").textContent = "";
    $("stStreak").textContent = "\u2014";
    $("stTier").textContent = "\u2014";
    updateActionButtons();
    return;
  }

  if (!onCorrectChain) {
    $("stBadge").textContent = "\u2014";
    $("stBadgeSub").textContent = "Switch to BNB Smart Chain to read your badge.";
    $("stStreak").textContent = "\u2014";
    $("stTier").textContent = "\u2014";
    updateActionButtons();
    return;
  }

  try {
    state.badgeId = await readContract.badgeOf(account);
  } catch (e) {
    state.badgeId = 0n;
  }

  if (state.badgeId === 0n) {
    $("stBadge").textContent = "None yet";
    $("stBadgeSub").textContent = "";
    $("stStreak").textContent = "\u2014";
    $("stTier").textContent = "\u2014";
    $("badgeEmpty").classList.remove("hidden");
    $("badgeFilled").classList.add("hidden");
  } else {
    $("stBadge").textContent = "#" + state.badgeId.toString();
    $("stBadgeSub").textContent = "Soulbound \u2022 non-transferable";
    try {
      const [streak, tier, lastDay] = await Promise.all([
        readContract.streakOf(state.badgeId),
        readContract.tierOf(state.badgeId),
        readContract.lastCheckInDayOf(state.badgeId)
      ]);
      state.streak = streak;
      state.tier = Number(tier);
      state.lastCheckInDay = lastDay;
      $("stStreak").textContent = streak.toString() + (streak === 1n ? " day" : " days");
      $("stStreakSub").textContent = lastDay === BigInt(utcDayNumber())
        ? "Checked in today"
        : "Last check-in day: " + lastDay.toString();
      $("stTier").textContent = CONFIG.tierNames[state.tier] || ("Tier " + state.tier);
      $("stTierSub").textContent = "Tier " + state.tier + " of 3";
    } catch (e) {
      $("stStreak").textContent = "\u2014";
      $("stTier").textContent = "\u2014";
    }
    await renderBadge(state.badgeId);
  }

  await refreshPublicStats();
  updateActionButtons();
}

function updateActionButtons() {
  const mintBtn = $("mintBtn");
  const checkInBtn = $("checkInBtn");
  const mintHint = $("mintHint");
  const checkInHint = $("checkInHint");

  // Mint: needs wallet + correct chain + deployed contract + Agent ID + no badge yet.
  let mintOk = false;
  if (!isDeployed()) {
    mintHint.textContent = "The Agent Badge contract has not been deployed yet — minting opens after deployment.";
  } else if (!account) {
    mintHint.textContent = "Connect your wallet to mint.";
  } else if (!onCorrectChain) {
    mintHint.textContent = "Switch to BNB Smart Chain to mint.";
  } else if (!state.agentIdHeld) {
    mintHint.textContent = "Your wallet does not hold an Agent ID, so it cannot mint a badge.";
  } else if (state.badgeId !== 0n) {
    mintHint.textContent = "You already own badge #" + state.badgeId.toString() + " — one badge per Agent ID holder.";
  } else {
    mintOk = true;
    mintHint.textContent = "Free mint — gas only. Your wallet will ask you to confirm the transaction.";
  }
  mintBtn.disabled = !mintOk;

  // Check-in: needs badge + not already checked in today.
  let checkInOk = false;
  if (!isDeployed()) {
    checkInHint.textContent = "";
  } else if (!account || state.badgeId === 0n) {
    checkInHint.textContent = state.badgeId === 0n && account ? "Mint a badge first, then check in daily." : "";
  } else if (!onCorrectChain) {
    checkInHint.textContent = "Switch to BNB Smart Chain to check in.";
  } else if (state.lastCheckInDay === BigInt(utcDayNumber())) {
    checkInHint.textContent = "Already checked in today. Come back tomorrow (UTC) to keep your streak.";
  } else {
    checkInOk = true;
    checkInHint.textContent = state.streak > 0n
      ? "Check in now to extend your " + state.streak.toString() + "-day streak."
      : "Check in now to start your streak.";
  }
  checkInBtn.disabled = !checkInOk;
}

/* ---------- badge display ---------- */

async function renderBadge(tokenId) {
  try {
    const uri = await readContract.tokenURI(tokenId);
    const meta = await parseTokenUri(uri);
    if (!meta) throw new Error("Unrecognized tokenURI format");
    if (meta.image) {
      const img = $("badgeImg");
      img.src = meta.image;
      img.alt = (meta.name || "Agent Badge") + " artwork";
    }
    $("badgeName").textContent = meta.name || ("Agent Badge #" + tokenId.toString());
    $("badgeDesc").textContent = meta.description || "";
    const attrsEl = $("badgeAttrs");
    attrsEl.innerHTML = "";
    if (Array.isArray(meta.attributes)) {
      for (const a of meta.attributes) {
        const div = document.createElement("div");
        div.className = "attr";
        const trait = document.createElement("span");
        trait.className = "trait";
        trait.textContent = a.trait_type || "";
        const val = document.createElement("span");
        val.textContent = String(a.value);
        div.appendChild(trait);
        div.appendChild(val);
        attrsEl.appendChild(div);
      }
    }
    $("badgeEmpty").classList.add("hidden");
    $("badgeFilled").classList.remove("hidden");
  } catch (e) {
    // Artwork could not be loaded — status panel above is still the source of truth.
    $("badgeEmpty").classList.remove("hidden");
    $("badgeFilled").classList.add("hidden");
  }
}

async function parseTokenUri(uri) {
  if (uri.startsWith("data:application/json;base64,")) {
    return JSON.parse(atob(uri.slice("data:application/json;base64,".length)));
  }
  if (uri.startsWith("data:application/json,")) {
    return JSON.parse(decodeURIComponent(uri.slice("data:application/json,".length)));
  }
  const res = await fetch(uri);
  if (!res.ok) throw new Error("tokenURI fetch failed (HTTP " + res.status + ")");
  return await res.json();
}

/* ---------- transactions ---------- */

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function sendTransaction(kind, fn) {
  const txBox = $("txBox");
  if (!signer || !onCorrectChain || !isDeployed()) return;
  const contractWithSigner = new ethers.Contract(CONFIG.contractAddress, badgeAbi, signer);
  $("mintBtn").disabled = true;
  $("checkInBtn").disabled = true;
  try {
    // Exactly one contract call, value 0, confirmed in the user's own wallet.
    const tx = await fn(contractWithSigner);
    showBox(txBox,
      "Transaction sent. Waiting for confirmation\u2026<br>Tx: <a href=\"" +
      escapeHtml(explorerTxUrl(tx.hash)) + "\" target=\"_blank\" rel=\"noopener\">" +
      escapeHtml(tx.hash) + "</a>");
    const receipt = await tx.wait();
    if (receipt && receipt.status === 1) {
      showBox(txBox,
        (kind === "mint" ? "Badge minted!" : "Checked in!") +
        "<br>Tx: <a href=\"" + escapeHtml(explorerTxUrl(tx.hash)) +
        "\" target=\"_blank\" rel=\"noopener\">" + escapeHtml(tx.hash) + "</a>",
        "success");
    } else {
      showBox(txBox,
        "Transaction was mined but reported a failure.<br>Tx: <a href=\"" +
        escapeHtml(explorerTxUrl(tx.hash)) + "\" target=\"_blank\" rel=\"noopener\">" +
        escapeHtml(tx.hash) + "</a>", "error");
    }
  } catch (e) {
    if (e && e.code === 4001) {
      showBox(txBox, "Transaction rejected in your wallet. Nothing was sent.", "error");
    } else if (e && e.code === "CALL_EXCEPTION") {
      showBox(txBox, "The contract rejected this transaction: " + escapeHtml(e.reason || e.message || "reverted"), "error");
    } else {
      showBox(txBox, "Transaction failed: " + escapeHtml(e && e.message ? e.message : String(e)), "error");
    }
  }
  await refreshStatus();
}

async function onMint() {
  if (!state.agentIdHeld || state.badgeId !== 0n) return;
  await sendTransaction("mint", (c) => c.mint());
}

async function onCheckIn() {
  if (state.badgeId === 0n) return;
  if (state.lastCheckInDay === BigInt(utcDayNumber())) return;
  await sendTransaction("checkIn", (c) => c.checkIn());
}

/* ---------- init ---------- */

function renderContractLine() {
  const line = $("contractLine");
  if (isDeployed()) {
    line.innerHTML = "Agent Badge contract: <a href=\"" + escapeHtml(CONFIG.explorerUrl) +
      "/address/" + escapeHtml(CONFIG.contractAddress) +
      "\" target=\"_blank\" rel=\"noopener\"><span class=\"mono\">" +
      escapeHtml(CONFIG.contractAddress) + "</span></a>";
  } else {
    line.innerHTML = "Agent Badge contract: <span class=\"muted\">not deployed yet</span>";
  }
}

async function init() {
  renderContractLine();
  if (typeof ethers === "undefined") {
    showBox($("connectMsg"), "Failed to load the ethers library from the CDN. Check your connection and reload the page.", "error");
    return;
  }
  try {
    await loadAbi();
  } catch (e) {
    showBox($("connectMsg"), "Could not load the contract ABI (abi.json). " + escapeHtml(e.message || String(e)), "error");
    return;
  }
  setupReadContracts();
  await refreshPublicStats();
  updateActionButtons();

  if (!hasProvider()) {
    $("noProviderBox").classList.remove("hidden");
    $("connectBtn").disabled = true;
    setNetPill(null, CONFIG.chainName + " \u2022 No wallet detected");
  }

  $("connectBtn").addEventListener("click", connectWallet);
  $("switchBtn").addEventListener("click", switchToBsc);
  $("mintBtn").addEventListener("click", onMint);
  $("checkInBtn").addEventListener("click", onCheckIn);
}

document.addEventListener("DOMContentLoaded", init);
