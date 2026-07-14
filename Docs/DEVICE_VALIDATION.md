# Device validation — production sign-off checklist

Run on a physical iPhone with Dynamic Island. The UI baseline is iPhone 17
standard on iOS 26; the currently connected iPhone Air remains the hardware
runtime target for microphone, haptics and background-intent checks.
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
- [ ] Say "p-p-p" → the compact ribbon spikes within ~300 ms.
- [ ] Whisper → small but visible motion; cover the mic → the ribbon settles
      immediately (proves levels are real).
- [ ] Silence → the ribbon settles to its resting rail AND console shows island
      updates being skipped (change-gating works).
- [ ] Normal speech → the 24-point ribbon reads as continuous flow, no visible
      500 ms steps. If steppy: raise the burst window in
      `FlowBridgeCoordinator.startIslandTick`.

Narrative arc (one uninterrupted run):
- [ ] Trigger → island lights < 400 ms with the resting membrane → speak → live
      coral wave + streaming words (head-truncated, no layout jumps) → stop →
      frozen decode-blue wave → refine-gold wave + "REFINING" → delivered-mint
      check bounce + "N words · Ns" → auto-dismiss after 6 s.
- [ ] Timer is monospaced with zero width wobble; at 9:00 elapsed it flips
      to an amber countdown ("ENDING SOON").
- [ ] Long-press mid-recording → expanded view: transcript legible at arm's
      length; **Finish from the island actually stops the session**.
- [ ] Pause from the app → expanded island shows one primary **Resume** action;
      resume continues the same session and timer without losing words.
- [ ] Delivered action dictation (event/reminder/message/email) → expanded
      island replaces the concise fallback with one contextual verb; tapping
      it performs or opens the expected system destination.
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

- [ ] Living Voice Field reacts to the real voice (cover mic → membrane
      settles), breathes when idle, tightens while processing and becomes a
      delivered rail without swapping geometry.
- [ ] The ordered color story is unmistakable without becoming noisy: violet
      ready → coral listening → blue decoding → gold refinement → mint
      delivery. Field, seam, room, CTA and island agree in every phase.
- [ ] Voice Field, transcript and contextual actions read as one continuous
      surface; no nested card stack returns in any state.
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

- [ ] VoiceOver: Living Voice Field announces state and result; island content readable.
- [ ] Reduce Motion: membrane travel and breathing stop while state text and
      color remain; island changes cross-fade instead of springing; onboarding reveals
      flatten to fades.
- [ ] Reduce Transparency: solid surfaces replace materials everywhere.
- [ ] Dynamic Type AX5: no clipped or overlapping text in app screens.

## 5. Known deferred items

- Engine switch applies from the next dictation; verify a running session never
  changes provider underneath the user.
- Voice-peak haptics ship default-OFF (Settings → Touch).
- The island intentionally exposes one primary action per phase. Pause stays
  in-app; the island exposes Resume only when the session is already paused.
