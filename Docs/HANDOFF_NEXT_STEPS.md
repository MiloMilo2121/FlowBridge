# FlowBridge — Handoff per il prossimo agent

> Aggiornato: 6 luglio 2026 · Da leggere insieme a [ROADMAP_V2.md](ROADMAP_V2.md), [KILLER_FEATURES_V2.md](KILLER_FEATURES_V2.md), [ARCHITECTURE.md](ARCHITECTURE.md) e [CODE_REVIEW_2026-07.md](CODE_REVIEW_2026-07.md) (quattro giri di review, findings chiusi/aperti).

## Stato del repository

| Cosa | Dove |
|---|---|
| V1 (dettatura base funzionante) → V2 completa (Fasi 0–3) + 4 giri di review | `main` (PR #1–#5 mergiate) |
| Quarto giro: red-team, dead-code, guardia tastiera, CI, MetricKit, a11y, Precision turbo, CloudEngine opt-in | branch `claude/v3-hardening` → **PR #6** (base: main) |

Cosa è stato verificato e cosa no:
- ✅ Il framework condiviso (`FlowBridgeShared`) compila con Swift 6.0.3 su Linux, i test-check a runtime (`swift run FlowBridgeSharedCheck`) passano, e ci sono unit test XCTest (37) per WER, safety buffer, vocabolario, statistiche, tono, cronologia, comandi vocali.
- ✅ C'è una **CI GitHub Actions** (`.github/workflows/ci.yml`): job Linux (container swift:6.0 — build, test, SharedCheck) e job macOS (xcodegen + xcodebuild simulatore senza firma). Il job macOS è il primo posto dove vedere gli errori attesi dell'SDK iOS.
- ⚠️ I target iOS (app, tastiera, share, widgets) **non sono mai stati compilati**: questo ambiente non ha l'SDK iOS. Aspettarsi errori da sistemare al primo build in Xcode.
- ⚠️ Nulla è mai girato su un device reale.

## Vincoli non negoziabili (non violarli mai)

1. **On-device di default; la rete è vietata salvo l'unica eccezione deliberata.** `NetworkGuard` resta installato ovunque e blocca tutto; l'unico varco è il **CloudEngine opt-in** (OFF di default, consenso esplicito, whitelist del solo host provider via `CloudGate`, badge visibile in registrazione). **Le extension non possono MAI raggiungere la rete** (`CloudGate.enableForAppProcess()` è chiamato solo dall'app). Nessun download di modelli a runtime; nessuna telemetria remota (MetricKit è locale e opt-in, condivisione solo manuale).
2. **La keyboard extension non registra audio e non carica modelli** (vietato dalla piattaforma: niente mic per entitlement, ~60–70MB di tetto memoria). L'app registra, la tastiera inserisce.
3. **Avvio in background = Live Activity obbligatoria** per tutta la durata della registrazione (`AudioRecordingIntent`): se l'activity muore, iOS uccide l'audio.
4. **Il transcript grezzo non si perde mai**: ogni percorso di errore del polisher/comandi ritorna il verbatim; `rawText` resta sul record.
5. **Codice V1 preservato**: le modifiche sono additive; Whisper resta il motore di default finché il benchmark non decide diversamente.

## ⚠️ Decisione pre-submit obbligatoria: Full Access della tastiera

Apple rigetta le tastiere il cui *core* non funziona senza Full Access (è
successo a WhisperPad). La nostra tastiera oggi ha un'unica funzione — leggere
il transcript dall'App Group — e quella richiede Full Access. **Prima di
inviare in review** va deciso: aggiungere una funzione base che funzioni senza
Full Access, oppure riposizionare la tastiera come componente opzionale. Non è
un problema di codice ma di posizionamento: deciderlo con calma, non davanti al
rigetto.

## TODO in ordine di priorità

### 0. Preflight (fai PRIMA di aprire Xcode)
- [ ] Su un Mac con Xcode 26: `./scripts/preflight.sh`. Fa tutto in sequenza e si ferma al primo errore: verifica toolchain → `swift build`+`swift test` (36 test) → `xcodegen generate` → `xcodebuild` di **tutti** i target iOS per simulatore → test iOS su simulatore. Nessuna firma, nessun device. Se passa, i file scritti contro l'SDK iOS 26 (`AppleSpeechEngine`, `TranscriptPolisher`) sono validati.

### 1. Primo build in Xcode (bloccante per tutto il resto)
- [ ] `./scripts/preflight.sh` verde (v. sopra). In alternativa, manualmente:
- [ ] `brew install xcodegen && xcodegen generate` — **obbligatorio**: il target `FlowBridgeWidgets` esiste solo in `project.yml`; il `.xcodeproj` committato **non** lo contiene (verificato). Aprire il `.xcodeproj` senza rigenerare fa mancare Live Activity/Dynamic Island.
- [ ] `./scripts/fetch-whisper-small.sh` per il modello (serve a runtime, non per compilare). Facoltativo: `./scripts/fetch-whisper-precision.sh` per il modello Precision (large-v3-turbo, ~626MB) — senza, il motore Precision ricade sul bundled.
- [ ] Team di firma su tutti i target + App Group `group.com.marcomilanello.flowbridge` su app, keyboard, share **e widgets**.
- [ ] Compilare e sistemare gli errori attesi, concentrati in due file scritti contro la superficie API documentata di iOS 26 ma mai validati con l'SDK:
  - `Sources/FlowBridgeApp/AppleSpeechEngine.swift` (SpeechAnalyzer/SpeechTranscriber/AssetInventory/AnalyzerInput: verificare firme di `start(inputSequence:)`, `analyzeSequence(from:)`, `finalizeAndFinish…`, preset, option sets)
  - `Sources/FlowBridgeApp/TranscriptPolisher.swift` (FoundationModels: `@Generable`/`@Guide`, `LanguageModelSession.respond(to:generating:options:)`, `prewarm()`, `GenerationOptions(sampling: .greedy)`)
  - Possibili aggiustamenti minori anche in: `DictationIntents.swift` (`AudioRecordingIntent`/`ForegroundContinuableIntent` + `requestToContinueInForeground()`), `DictationLiveActivity.swift` (`supplementalActivityFamilies`), `WhisperEngine.swift` (`DecodingOptions.promptTokens`, `tokenizer.encode(text:)`, `specialTokens.specialTokenBegin`, protocollo `AudioProcessing`/`audioSamples`).
  - Dal quarto giro, anche i file nuovi mai compilati contro l'SDK: `CloudEngine.swift` (AVAudioEngine + URLSession multipart), `DiagnosticsCollector.swift` (MetricKit), `KeychainStore.swift` (Security).
- [ ] Far girare i test XCTest (`FlowBridgeSharedTests`) su simulatore.

### 2. Spike su device reale (i "gate" della roadmap)
- [ ] **Spike `AudioRecordingIntent`** (il più importante): Action Button → registrazione parte in background senza aprire l'app? Testare: primo avvio senza permesso (deve cadere nel fallback foreground), device bloccato, app killata, durante altra app in audio. Se inaffidabile → fallback `openAppWhenRun = true` (già pronto: `ToggleDictationIntent`).
- [ ] **Dynamic Island**: verificare timer, anteprima streaming (frequenza update locali accettabile?), bottone Stop (esegue nel processo app?), comportamento a schermo bloccato.
- [ ] **Recovery**: uccidere l'app mentre registra → al riavvio la dettatura viene recuperata dal safety buffer? Verificare che il WAV sia leggibile e che il gap-on-purge di WhisperKit (documentato in ARCHITECTURE.md) non degradi troppo.
- [ ] **Tastiera**: Darwin notifications arrivano nell'extension? Il diff incrementale non sfarfalla? Full Access + App Group ok?
- [ ] **Spike Whisper Mode** (killer feature #5, non ancora implementata): misurare WER parlando a bassissimo volume; decidere gain/VAD.
- [ ] **CloudEngine** (opt-in): con una chiave ElevenLabs vera — consenso mostrato una volta sola? badge visibile? upload allo stop ok? upload fallito (modalità aereo a metà) → WAV recuperato al riavvio? disattivando il toggle il motore torna a Whisper?
- [ ] **MetricKit**: i report arrivano (iOS li consegna ~1 volta/giorno)? ShareLink funziona?

### 3. Benchmark (decide il motore di default)
- [ ] Registrare il set italiano in `Resources/Benchmark` (voce normale, sussurro, rumore strada, vocabolario tecnico — formato: `nome.wav` + `nome.txt`, v. README della cartella).
- [ ] Eseguire `BenchmarkHarness` su WhisperEngine vs AppleSpeechEngine; se Apple vince su WER italiano + latenza, promuoverlo a default (`EnginePreference`).

### 4. Dogfood (2 settimane minimo prima di procedere)
- [ ] Usare FlowBridge come dettatura quotidiana. Criteri della Definition of Done V2.0 (roadmap §7): press→prima parola < 1,5s; stop→testo pulito < 2s; **zero dettature perse**; dettatura completa senza mai vedere l'app.
- [ ] Annotare frizioni reali → diventano il backlog di rifinitura.

### 5. Lavori rimasti dalle Fasi 2–3 (non ancora implementati)
- [ ] **Localizzazione IT/EN** con String Catalog (le stringhe UI oggi sono in inglese hardcoded).
- [ ] **Paywall + IAP una tantum** (~€29,99, hard paywall dopo trial — v. roadmap §9): creare prodotto in App Store Connect, StoreKit 2, schermata "Perché niente abbonamento".
- [ ] **"Ritrascrivi con Precision"**: richiede una retention audio configurabile (default 24h poi auto-delete) — progettare prima la retention, poi il bottone in cronologia.
- [ ] **`contextualStrings` su DictationTranscriber**: il vocabolario oggi fa bias solo su Whisper; aggiungere il modulo DictationTranscriber come fallback con vocabolario nella famiglia Apple.
- [ ] Icona app, screenshot con Dynamic Island, video demo in modalità aereo, testo App Store (bozza IT già in ROADMAP_V2.md §4.2 — fare versione EN).

### 6. Backlog post-lancio (in ordine di valore, dalle killer feature)
- Learn-from-Edit (#9): diff locale sulle correzioni → proposta di aggiunta al vocabolario (TipKit).
- Interactive snippet iOS 26 (#14): risultato dettatura sopra qualsiasi schermata senza aprire l'app.
- Azioni dal parlato (#16): estrazione promemoria/eventi con guided generation → EventKit/Reminders (opt-in, mai scritture automatiche).
- Ricerca semantica nella cronologia (#17): NLEmbedding on-device.
- Tap-to-listen (#18): `audioTimeRange` per-parola + retention audio.
- Orb in Metal + coreografia matchedGeometryEffect (UX spec §2.1/2.5) — oggi la UI è funzionale, non ancora "premium".
- Parakeet v3 / app macOS / modalità comando: solo dopo che la base è impeccabile.

## Comandi utili

```sh
# Verifica cross-platform (funziona anche su Linux con toolchain Swift 6)
swift build && swift run FlowBridgeSharedCheck

# Rigenerare il progetto Xcode (SEMPRE dopo aver aggiunto/rinominato file o toccato project.yml)
xcodegen generate

# Modello Whisper (bundled) e Precision (large-v3-turbo, opzionale)
./scripts/fetch-whisper-small.sh
./scripts/fetch-whisper-precision.sh
```

## Trappole note (imparate a caro prezzo)

- Il `.xcodeproj` è generato ma committato: i sorgenti sono folder-based, quindi **ogni file nuovo richiede `xcodegen generate`** (oppure la registrazione manuale nel pbxproj, come fatto finora da questo ambiente senza Mac).
- Le tastiere **non possono** leggere il bundle id dell'app host (API pubblica) — il tono per-app usa i trait del campo di testo, non cambiarlo in un lookup del bundle id.
- `SharedContainer` e `NetworkGuard` hanno guard `#if canImport` per il build Linux: mantenerli quando si tocca quel codice.
- Il flush del safety buffer salta i campioni purgati dallo stream (gap, non duplicazione) — è una scelta deliberata, documentata in ARCHITECTURE.md.
- I test XCTest esistenti di V1 (`TranscriptStoreTests` ecc.) hanno metodi senza prefisso `test` e quindi non girano: bug preesistente, da sistemare quando si tocca quel file.
- Le tre note vocali di contesto: l'utente (Marco) usa un iPhone Air (A19 Pro, 12GB, Action Button, Dynamic Island), parla italiano e inglese, e il target di qualità dichiarato è "feeling migliore di Wispr Flow".
