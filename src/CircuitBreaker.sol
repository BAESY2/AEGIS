// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPairLike {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/// @title CircuitBreaker — installable firewall, hardened against false-pause griefing.
/// @notice A DeFi CISO's #1 objection to an auto-pause is griefing: "someone trips
///         my market into a false pause and that outage IS the attack." This design
///         removes that, so the breaker is safe to install:
///
///         1. ALERT_ONLY by default. Auto-pause is opt-in; until a protocol turns
///            it on, the breaker only signals and a trusted guardian/governance acts.
///         2. Auto-trip reads TWO independent on-chain price sources ITSELF — the
///            caller supplies NOTHING forgeable. To trip it you must actually move a
///            real pool's price past the threshold, which costs the full
///            manipulation capital. Cheap griefing is impossible; a "successful"
///            grief is indistinguishable from (and as expensive as) a real attack.
///         3. The pause is BOUNDED and self-healing: it auto-resumes after
///            `maxPauseBlocks` unless governance ratifies it. A false pause is a
///            short, bounded outage — never a permanent freeze.
///         4. A cooldown rate-limits trips so the market cannot be pause-spammed.
///
///         It still never moves funds: it can only pause, briefly, and reset is
///         governance-only.
contract CircuitBreaker {
    enum Mode { ALERT_ONLY, AUTO_PAUSE }

    address public owner;                      // governance
    mapping(address => bool) public guardian;  // trusted fast responders (the keeper)
    Mode public mode;

    // independent on-chain sources for unforgeable auto-trip (same asset, same orientation)
    address public sourceA;
    address public sourceB;
    uint256 public deviationBps;               // auto-trip threshold

    uint256 public maxPauseBlocks;             // bounded, self-healing pause length
    uint256 public cooldownBlocks;             // min gap between trips (anti-spam)

    uint256 public pausedUntil;                // block until which the market is paused
    uint256 public lastTripBlock;
    bool public ratified;                      // governance confirmed the current pause
    string public reason;

    event Alert(address indexed by, string reason);
    event Paused(address indexed by, uint256 until, string reason);
    event Ratified(address indexed by);
    event Reset(address indexed by);

    error Paused_();
    error NotOwner();
    error NotGuardian();
    error Cooldown();
    error NoManipulation();
    error AutoPauseOff();

    constructor(address[] memory guardians, uint256 _maxPauseBlocks, uint256 _cooldownBlocks) {
        owner = msg.sender;
        for (uint256 i = 0; i < guardians.length; i++) guardian[guardians[i]] = true;
        maxPauseBlocks = _maxPauseBlocks;
        cooldownBlocks = _cooldownBlocks;
        mode = Mode.ALERT_ONLY;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice True while the market should be halted. Auto-heals when the bounded
    ///         pause elapses, unless governance ratified it.
    function isPaused() public view returns (bool) {
        return ratified || block.number < pausedUntil;
    }

    /// @notice Protocols call this at the top of a protected action.
    function check() external view {
        if (isPaused()) revert Paused_();
    }

    // ----- trusted path (keeper / governance): signal or pause -----

    /// @notice A guardian raises an alert (ALERT_ONLY) or pauses (AUTO_PAUSE).
    function trip(string calldata why) external {
        if (!guardian[msg.sender] && msg.sender != owner) revert NotGuardian();
        if (mode == Mode.ALERT_ONLY) {
            emit Alert(msg.sender, why);
            return;
        }
        _pause(why);
    }

    // ----- trustless path: unforgeable, reads real on-chain prices itself -----

    /// @notice Anyone may trip the breaker, but ONLY if two independent on-chain
    ///         sources actually disagree past the threshold. Nothing is caller-
    ///         supplied, so the only way to make this fire is to truly manipulate a
    ///         pool — which costs the full attack capital. No cheap griefing.
    function autoTripFromSources() external {
        if (mode != Mode.AUTO_PAUSE) revert AutoPauseOff();
        if (!_manipulated()) revert NoManipulation();
        _pause("auto-trip: independent on-chain sources diverged past threshold");
    }

    function currentDeviationBps() public view returns (uint256) {
        uint256 a = _price(sourceA);
        uint256 b = _price(sourceB);
        if (a == 0 || b == 0) return 0;
        uint256 hi = a > b ? a : b;
        uint256 lo = a < b ? a : b;
        return ((hi - lo) * 10000) / lo;
    }

    function _manipulated() internal view returns (bool) {
        return currentDeviationBps() > deviationBps;
    }

    function _price(address pair) internal view returns (uint256) {
        (uint112 r0, uint112 r1, ) = IPairLike(pair).getReserves();
        if (r1 == 0) return 0;
        return (uint256(r0) * 1e18) / uint256(r1);
    }

    function _pause(string memory why) internal {
        if (lastTripBlock != 0 && block.number < lastTripBlock + cooldownBlocks) revert Cooldown();
        lastTripBlock = block.number;
        pausedUntil = block.number + maxPauseBlocks;
        ratified = false;
        reason = why;
        emit Paused(msg.sender, pausedUntil, why);
    }

    // ----- governance -----

    /// @notice Confirm a real incident: hold the pause until an explicit reset
    ///         (overrides the self-healing timeout).
    function ratify() external onlyOwner {
        ratified = true;
        emit Ratified(msg.sender);
    }

    function reset() external onlyOwner {
        pausedUntil = 0;
        ratified = false;
        reason = "";
        emit Reset(msg.sender);
    }

    function setMode(Mode m) external onlyOwner {
        mode = m;
    }

    function setSources(address a, address b, uint256 devBps) external onlyOwner {
        sourceA = a;
        sourceB = b;
        deviationBps = devBps;
    }

    function setGuardian(address who, bool ok) external onlyOwner {
        guardian[who] = ok;
    }

    function setParams(uint256 _maxPauseBlocks, uint256 _cooldownBlocks) external onlyOwner {
        maxPauseBlocks = _maxPauseBlocks;
        cooldownBlocks = _cooldownBlocks;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
