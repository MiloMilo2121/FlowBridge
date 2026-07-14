# FlowBridge — Handoff per il prossimo agent

> Aggiornato: 14 luglio 2026 · Da leggere insieme a [DESIGN.md](../DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md) e [DEVICE_VALIDATION.md](DEVICE_VALIDATION.md). `KILLER_FEATURES_V2.md` resta contesto storico; per UI, materiali e motion prevale `DESIGN.md`.

## Stato del repository

| Cosa | Dove |
|---|---|
| V1 + V2 Fasi 0–3 (PR #1 e #2 merged) | `main` |
| **Voice OS UI + readiness install + hardening produzione isola** | branch `iphone-premium-app-install` |

Il branch attuale contiene, oltre alle Fasi 0–3:
- **Dynamic Island con waveform reale** (livelli mic quantizzati nel ContentState, tick 4→2Hz change-gated, narrativa di fase completa, staleness, orfani uccisi al bootstrap, update serializzati) — v. `DictationLiveActivity.swift`, `DictationActivityController.swift`, `AudioLevelMeter.swift`.
- **Living Voice Field**: una membrana orizzontale audio-reattiva sopravvive a idle, ascolto, processing e delivery; transcript e azioni vivono nella stessa superficie. Una color story funzionale — viola → corallo → blu → oro → menta — rende immediatamente leggibili ascolto, decoding, refinement e consegna. Onboarding, History, Settings, Stats, Privacy, keyboard e widget condividono geometria, materiali e motion tramite `DESIGN.md`.
- **Dynamic Island contestuale**: una sola azione primaria per stato (Finish, Resume oppure event/reminder/message/email dopo la delivery), con fallback Tighter quando non emerge un intento affidabile.
- **Repo pronto all'install**: App Group in tutti gli entitlements (via `project.yml properties`), modello Whisper Small in `Resources/WhisperModels/WhisperSmall/` (472MB, git-ignored, folder reference), `Assets.xcassets` con icona generata (script `scripts/generate-app-icon.py`), scheme headless, chiavi Live Activity frequent updates.

Cosa è verificato e cosa no:
- ✅ App, keyboard, share extension, widget e Live Activity compilano con Xcode 26 per iPhone 17 Simulator.
- ✅ `FlowBridgeSharedTests`: 51/51 passano su iPhone 17 Simulator; il target ora genera correttamente il proprio Info.plist.
- ✅ Validazione visiva light, dark, Dynamic Type Accessibility Large e Increase Contrast completata sul canvas iPhone 17 standard.
- ✅ Build arm64 generica per iOS completata con firma disabilitata: tutto il codice device compila, incluse app ed estensioni.
- ⚠️ La build firmata arriva al CodeSign, poi il Portachiavi macOS rifiuta la chiave con `errSecInternalComponent`. Per installare: sbloccare il Portachiavi e scegliere **Consenti sempre** per `codesign`, quindi rilanciare la build firmata.
- ⚠️ Il controllo touch automatizzato su device richiede il DebugBridge gstack (`@Observable/@Snapshotable`), che questo progetto non integra. La checklist hardware resta in `DEVICE_VALIDATION.md`.

## Vincoli non negoziabili (non violarli mai)

1. **On-device per default, cloud solo per scelta esplicita.** `NetworkGuard` protegge i percorsi locali; una richiesta cloud è ammessa solo quando l'utente salva una key e seleziona un engine cloud. Nessun download di modelli o telemetria a sorpresa.
2. **La keyboard extension non registra audio e non carica modelli.** L'app registra, la tastiera inserisce.
3. **Avvio in background = Live Activity obbligatoria** per tutta la registrazione (`AudioRecordingIntent`): se l'activity muore, iOS uccide l'audio.
4. **Il transcript grezzo non si perde mai**: ogni percorso d'errore ritorna il verbatim; `rawText` resta sul record.
5. **Whisper resta il motore di default** finché il benchmark non decide diversamente. Il motore scelto nelle Settings si applica dalla dettatura successiva, mai a metà sessione.

## TODO in ordine di priorità

### 1. Gate immediato: hardware
- [ ] Eseguire l'intera [DEVICE_VALIDATION.md](DEVICE_VALIDATION.md) su iPhone con Dynamic Island.
- [ ] Verificare in particolare background start a telefono bloccato, Resume dall'isola, azione contestuale post-delivery e keyboard in un'app host reale.
- [ ] Profilare una dettatura di 10 minuti con Energy Log.

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
Learn-from-Edit (TipKit) · interactive snippet iOS 26 · ricerca semantica (NLEmbedding) · tap-to-listen · Parakeet v3 / macOS. Azioni dal parlato, pausa/resume ed engine switch dalla dettatura successiva sono già implementati.

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
