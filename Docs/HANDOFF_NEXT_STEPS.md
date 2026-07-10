# FlowBridge — Handoff per il prossimo agent

> Aggiornato: 3 luglio 2026 · Da leggere insieme a [ROADMAP_V2.md](ROADMAP_V2.md), [KILLER_FEATURES_V2.md](KILLER_FEATURES_V2.md), [ARCHITECTURE.md](ARCHITECTURE.md) e [DEVICE_VALIDATION.md](DEVICE_VALIDATION.md).

## Stato del repository

| Cosa | Dove |
|---|---|
| V1 + V2 Fasi 0–3 (PR #1 e #2 merged) | `main` |
| **Layer premium + readiness install + hardening produzione isola** | branch `iphone-premium-app-install` (commit `e7fd03d` + `ebbf8c6`) |

Il branch attuale contiene, oltre alle Fasi 0–3:
- **Dynamic Island con waveform reale** (livelli mic quantizzati nel ContentState, tick 4→2Hz change-gated, narrativa di fase completa, staleness, orfani uccisi al bootstrap, update serializzati) — v. `DictationLiveActivity.swift`, `DictationActivityController.swift`, `AudioLevelMeter.swift`.
- **Layer premium in-app**: Orb reattiva alla voce, testo vivo, reveal raw→polished, CoreHaptics, stats giornaliere + streak + ticker + recap, History/Onboarding/Privacy Cockpit rifiniti.
- **Repo pronto all'install**: App Group in tutti gli entitlements (via `project.yml properties`), modello Whisper Small in `Resources/WhisperModels/WhisperSmall/` (472MB, git-ignored, folder reference), `Assets.xcassets` con icona generata (script `scripts/generate-app-icon.py`), scheme headless, chiavi Live Activity frequent updates.

Cosa è verificato e cosa no:
- ✅ `FlowBridgeShared` compila (SwiftPM, macOS + Linux), `swift run FlowBridgeSharedCheck` passa, tutti i sorgenti passano `swiftc -parse`.
- ✅ Test condivisi: nuovo `DictationDailyStatsTests` + fix del bug storico dei metodi senza prefisso `test` (ora girano tutti). `swift test` richiede Xcode (XCTest non è nei CLT).
- ⚠️ I target iOS **non sono mai stati compilati**: sul Mac manca Xcode (in arrivo, account Apple gratuito da creare al sign-in).
- ⚠️ Nulla è mai girato su device reale.

## Vincoli non negoziabili (non violarli mai)

1. **Zero rete sul percorso audio/testo.** `NetworkGuard` resta installato ovunque; nessun download di modelli a runtime; nessuna telemetria remota.
2. **La keyboard extension non registra audio e non carica modelli.** L'app registra, la tastiera inserisce.
3. **Avvio in background = Live Activity obbligatoria** per tutta la registrazione (`AudioRecordingIntent`): se l'activity muore, iOS uccide l'audio.
4. **Il transcript grezzo non si perde mai**: ogni percorso d'errore ritorna il verbatim; `rawText` resta sul record.
5. **Whisper resta il motore di default** finché il benchmark non decide diversamente. Nota: il motore scelto nelle Settings si applica **al riavvio dell'app** (il coordinator lo crea all'init — footer UI già onesto al riguardo).

## TODO in ordine di priorità

### 0. [MARCO] Xcode 26
Spazio liberato in corso (32GB liberi, target ~40). App Store → Xcode, poi:
```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch
```
Xcode → Settings → Accounts → Apple ID → Manage Certificates → “+” Apple Development.

### 1. Loop di compilazione (Claude, appena Xcode c'è)
- [ ] Team ID dal certificato (`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`, campo OU) → `DEVELOPMENT_TEAM` in `project.yml settings.base` → `xcodegen generate`.
- [ ] `xcodebuild -resolvePackageDependencies -project FlowBridge.xcodeproj -scheme FlowBridgeApp`
- [ ] Loop: `xcodebuild build -scheme FlowBridgeApp -destination 'generic/platform=iOS' -derivedDataPath .derived CODE_SIGNING_ALLOWED=NO -quiet`
- [ ] Errori attesi (in ordine di probabilità): `AppleSpeechEngine.swift` (superficie SpeechAnalyzer/SpeechTranscriber), `TranscriptPolisher.swift` (FoundationModels), `WhisperEngine.swift` (drift WhisperKit 1.0 — leggere il sorgente in `.derived/SourcePackages/checkouts/`, incl. verifica `AudioProcessing.audioSamples` usato dal metering), `DictationLiveActivity.swift` (`keylineTint`, `activityFamily`, preview macro), residui strict-concurrency Swift 6. Gli intent hanno già `static let`.
- [ ] `swift test` (ora include daily stats + i test V1 riparati).
- [ ] Verifica bundle: 3 `.appex` in `PlugIns/`, `WhisperModels/WhisperSmall/` nel `.app`.

### 2. Firma + install (Claude + [MARCO] su iPhone)
- [ ] Build con `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` (crea 4 App ID + App Group sul personal team; se il flusso headless si blocca, un Cmd-R da Xcode GUI sblocca).
- [ ] iPhone: cavo + Trust, Developer Mode ON, trust del certificato dopo l'install.
- [ ] Setup on-device: tastiera + Full Access, Action Button → controllo "FlowBridge Dictation", Live Activities ON.
- [ ] Limiti free team: profili 7 giorni (reinstall settimanale), max 3 app, max 10 App ID/7gg (non churnare i bundle id).

### 3. Validazione su device
Seguire **[DEVICE_VALIDATION.md](DEVICE_VALIDATION.md)** (gate AudioRecordingIntent, gate premium dell'isola, recovery, a11y, energia). È la checklist di firma "produzione".

### 4. Benchmark (decide il motore di default)
- [ ] Registrare il set italiano in `Resources/Benchmark`; `BenchmarkHarness` Whisper vs AppleSpeech; promuovere il vincitore.

### 5. Dogfood (2 settimane minimo)
- [ ] Definition of Done V2.0: press→prima parola <1,5s; stop→testo pulito <2s; zero dettature perse; dettatura completa senza aprire l'app.

### 6. Lavori rimasti verso il lancio
- [ ] Localizzazione IT/EN (String Catalog) — le stringhe nuove del layer premium sono in inglese come il resto.
- [ ] Paywall + IAP una tantum (~€29,99) — richiede account Apple **a pagamento**.
- [ ] Retention audio + "Ritrascrivi con Precision"; `contextualStrings` su DictationTranscriber; screenshot/video/copy App Store.

### 7. Backlog post-lancio
Learn-from-Edit (TipKit) · interactive snippet iOS 26 · azioni dal parlato (EventKit) · ricerca semantica (NLEmbedding) · tap-to-listen · pausa nell'isola · Orb in Metal + matchedGeometryEffect · engine switch a caldo · Parakeet v3 / macOS.

## Comandi utili

```sh
swift build && swift run FlowBridgeSharedCheck   # verifica cross-platform
swift test                                        # richiede Xcode attivo
xcodegen generate                                 # SEMPRE dopo file nuovi/rinominati o project.yml
./scripts/fetch-whisper-small.sh                  # modello (già staged)
.build/iconenv/bin/python scripts/generate-app-icon.py  # rigenerare l'icona
```

## Trappole note (imparate a caro prezzo)

- Il `.xcodeproj` è generato: **ogni file nuovo richiede `xcodegen generate`**. Entitlements e Info.plist si toccano SOLO via `project.yml` (`entitlements.properties` / `info.properties`) — xcodegen riscrive i file generati.
- `Resources/WhisperModels` e `Resources/Benchmark` devono restare `type: folder` in `project.yml`, o il modello (git-ignored, fetchato dopo il generate) non finisce nel bundle.
- ActivityKit esiste su macOS ma i tipi sono iOS-only: le guardie condivise sono `#if canImport(ActivityKit) && os(iOS)` — non rimuovere `&& os(iOS)` o il check SwiftPM su Mac esplode.
- Ogni chiamata ActivityKit del controller passa dalla catena `enqueue` (ordering garantito): non aggiungere `Task { activity.update(...) }` sciolti.
- Gli snapshot live vanno sempre filtrati per `sessionID` (dopo un crash lo store può contenere uno snapshot `isRecording` della sessione morta).
- Le tastiere non possono leggere il bundle id dell'app host: il tono per-app usa i trait del campo di testo.
- Il flush del safety buffer salta i campioni purgati (gap, non duplicazione) — deliberato, v. ARCHITECTURE.md.
- Marco usa un iPhone Air (A19 Pro, Action Button, Dynamic Island), parla italiano e inglese; target di qualità dichiarato: "feeling migliore di Wispr Flow".
