# Device validation — production sign-off checklist

Run on a physical iPhone with Dynamic Island (target: iPhone Air, iOS 26).
Nothing in this list is verifiable in the simulator: update budgets,
background intents, haptics, ProMotion and real microphone dynamics are
device-only.

## 1. Background start (the make-or-break gate)

- [ ] Action Button with the app **killed** and the phone **locked** →
      recording starts in the background, island appears, app never opens.
- [ ] Same, without microphone permission granted → falls back to opening
      the app in the foreground (no silent failure).
- [ ] Same, while another app plays audio → their audio ducks, recording
      starts.
- [ ] Control Center control and Lock Screen control both start dictation.

## 2. Dynamic Island — premium gates

Waveform truth:
- [ ] Say "p-p-p" → compact bars spike within ~300 ms.
- [ ] Whisper → small but visible motion; cover the mic → bars die
      immediately (proves levels are real).
- [ ] Silence → bars settle to resting dots AND console shows island
      updates being skipped (change-gating works).
- [ ] Normal speech → the 24-bar strip reads as continuous flow, no visible
      500 ms steps. If steppy: raise the burst window in
      `FlowBridgeCoordinator.startIslandTick`.

Narrative arc (one uninterrupted run):
- [ ] Trigger → island lights < 400 ms with resting bars → speak → live
      wave + streaming words (head-truncated, no layout jumps) → stop →
      violet frozen wave + "POLISHING" → green check bounce + "N words · Ns"
      → auto-dismiss after 6 s.
- [ ] Timer is monospaced with zero width wobble; at 9:00 elapsed it flips
      to an amber countdown ("ENDING SOON").
- [ ] Long-press mid-recording → expanded view: transcript legible at arm's
      length; **Stop from the island actually stops the session**.
- [ ] Stop from the Lock Screen works (after unlock, per platform rule).
- [ ] Recording dot keeps pulsing during long silence (budget-free
      liveness).

Surfaces:
- [ ] Lock Screen: legible on light and dark wallpapers.
- [ ] StandBy at night: system red-shift applies (no fights from a custom
      background tint).
- [ ] Minimal: start another app's Live Activity → FlowBridge minimal dot
      reads at ~20 pt.
- [ ] Paired Watch Smart Stack shows the `.small` relay.

Failure honesty:
- [ ] Stop after total silence → island shows "Nothing heard — the
      microphone stayed silent." in orange, then dismisses (never a silent
      vanish).
- [ ] Force-kill the app mid-recording → within ~15 s the island dims and
      shows "Recording interrupted — open FlowBridge"; Stop is hidden.
- [ ] Relaunch after the kill → the orphan island is dismissed at launch,
      safety-buffer recovery delivers the text (`Source.recovered`).
- [ ] No zombie island ever survives a crash + relaunch cycle.

Energy:
- [ ] Instruments → Energy Log over a 10-minute dictation: island updates
      invisible next to ASR cost; no thermal state change attributable to
      the tick.

## 3. In-app premium

- [ ] Orb reacts to the real voice (cover mic → glow dies), breathes when
      idle, crystallizes on ready.
- [ ] Words materialize as you speak; raw→polished reveal lands < 2 s after
      stop; "N words cleaned" caption toggles the verbatim.
- [ ] Time-given-back ticker rolls up after every session; streak day 1
      appears after the first dictation.
- [ ] Haptics: heartbeat up/down, crystal on ready, rumble on failure —
      each distinct, none reused. CHHapticEngine plays while the `.record`
      session is active (if not: HapticPlayer falls back to UIKit
      generators — verify the fallback fires).
- [ ] Keyboard: live text streams without flicker; insert + return work
      (requires Full Access).

## 4. Accessibility

- [ ] VoiceOver: Orb announces state and result; island content readable.
- [ ] Reduce Motion: Orb ring/ripples replaced by level-tracking glow;
      island bars cross-fade instead of springing; onboarding reveals
      flatten to fades.
- [ ] Reduce Transparency: solid surfaces replace materials everywhere.
- [ ] Dynamic Type AX5: no clipped or overlapping text in app screens.

## 5. Known deferred items

- Engine switch applies at next launch (footer says so). Live engine swap
  is a post-install improvement.
- Voice-peak haptics ship default-OFF (Settings → Touch).
- Pause in the island: deliberately not built (a premium Stop beats a
  flaky Pause; WhisperKit's stream has no pause API).
