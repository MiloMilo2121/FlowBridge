# FlowBridge — Handoff per il prossimo agent

> Aggiornato: 2 luglio 2026 · Da leggere insieme a [ROADMAP_V2.md](ROADMAP_V2.md), [KILLER_FEATURES_V2.md](KILLER_FEATURES_V2.md) e [ARCHITECTURE.md](ARCHITECTURE.md).

## Stato del repository

| Cosa | Dove |
|---|---|
| V1 (dettatura base funzionante) | `main` |
| Roadmap V2 + Fasi 0–1 implementate | branch `claude/flobridge-v2-roadmap-2172rk` → **PR #1** (base: main) |
| Fasi 2–3 implementate | branch `claude/flowbridge-v2-phase2-3` → **PR #2** (base: PR #1, stacked) |

**Ordine di merge: prima la #1, poi la #2** (GitHub ripunta la #2 su main da solo).

Cosa è stato verificato e cosa no:
- ✅ Il framework condiviso (`FlowBridgeShared`) compila con Swift 6.0.3 su Linux, i test-check a runtime (`swift run FlowBridgeSharedCheck`) passano, e ci sono unit test XCTest per WER, safety buffer, vocabolario, statistiche, tono, cronologia, comandi vocali.
- ⚠️ I target iOS (app, tastiera, share, widgets) **non sono mai stati compilati**: questo ambiente non ha l'SDK iOS. Aspettarsi errori da sistemare al primo build in Xcode.
- ⚠️ Nulla è mai girato su un device reale.

## Vincoli non negoziabili (non violarli mai)

1. **Zero rete sul percorso audio/testo.** `NetworkGuard` resta installato ovunque; nessun download di modelli a runtime; nessuna telemetria remota. È il posizionamento del prodotto ("privato per architettura"), non un dettaglio.
2. **La keyboard extension non registra audio e non carica modelli** (vietato dalla piattaforma: niente mic per entitlement, ~60–70MB di tetto memoria). L'app registra, la tastiera inserisce.
3. **Avvio in background = Live Activity obbligatoria** per tutta la durata della registrazione (`AudioRecordingIntent`): se l'activity muore, iOS uccide l'audio.
4. **Il transcript grezzo non si perde mai**: ogni percorso di errore del polisher/comandi ritorna il verbatim; `rawText` resta sul record.
5. **Codice V1 preservato**: le modifiche sono additive; Whisper resta il motore di default finché il benchmark non decide diversamente.

## TODO in ordine di priorità

### 1. Primo build in Xcode (bloccante per tutto il resto)
- [ ] `git checkout claude/flowbridge-v2-phase2-3` su un Mac con Xcode 26.
- [ ] `brew install xcodegen && xcodegen generate` — **obbligatorio**: il target `FlowBridgeWidgets` esiste solo in `project.yml`; il `.xcodeproj` committato contiene già i file di app/shared/tests ma non il target widgets.
- [ ] `./scripts/fetch-whisper-small.sh` per il modello.
- [ ] Team di firma su tutti i target + App Group `group.com.marcomilanello.flowbridge` su app, keyboard, share **e widgets**.
- [ ] Compilare e sistemare gli errori attesi, concentrati in due file scritti contro la superficie API documentata di iOS 26 ma mai validati con l'SDK:
  - `Sources/FlowBridgeApp/AppleSpeechEngine.swift` (SpeechAnalyzer/SpeechTranscriber/AssetInventory/AnalyzerInput: verificare firme di `start(inputSequence:)`, `analyzeSequence(from:)`, `finalizeAndFinish…`, preset, option sets)
  - `Sources/FlowBridgeApp/TranscriptPolisher.swift` (FoundationModels: `@Generable`/`@Guide`, `LanguageModelSession.respond(to:generating:options:)`, `prewarm()`, `GenerationOptions(sampling: .greedy)`)
  - Possibili aggiustamenti minori anche in: `DictationIntents.swift` (`AudioRecordingIntent`/`ForegroundContinuableIntent` + `requestToContinueInForeground()`), `DictationLiveActivity.swift` (`supplementalActivityFamilies`), `WhisperEngine.swift` (`DecodingOptions.promptTokens`, `tokenizer.encode(text:)`, `specialTokens.specialTokenBegin`, protocollo `AudioProcessing`/`audioSamples`).
- [ ] Far girare i test XCTest (`FlowBridgeSharedTests`) su simulatore.

### 2. Spike su device reale (i "gate" della roadmap)
- [ ] **Spike `AudioRecordingIntent`** (il più importante): Action Button → registrazione parte in background senza aprire l'app? Testare: primo avvio senza permesso (deve cadere nel fallback foreground), device bloccato, app killata, durante altra app in audio. Se inaffidabile → fallback `openAppWhenRun = true` (già pronto: `ToggleDictationIntent`).
- [ ] **Dynamic Island**: verificare timer, anteprima streaming (frequenza update locali accettabile?), bottone Stop (esegue nel processo app?), comportamento a schermo bloccato.
- [ ] **Recovery**: uccidere l'app mentre registra → al riavvio la dettatura viene recuperata dal safety buffer? Verificare che il WAV sia leggibile e che il gap-on-purge di WhisperKit (documentato in ARCHITECTURE.md) non degradi troppo.
- [ ] **Tastiera**: Darwin notifications arrivano nell'extension? Il diff incrementale non sfarfalla? Full Access + App Group ok?
- [ ] **Spike Whisper Mode** (killer feature #5, non ancora implementata): misurare WER parlando a bassissimo volume; decidere gain/VAD.

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

# Modello Whisper
./scripts/fetch-whisper-small.sh
```

## Trappole note (imparate a caro prezzo)

- Il `.xcodeproj` è generato ma committato: i sorgenti sono folder-based, quindi **ogni file nuovo richiede `xcodegen generate`** (oppure la registrazione manuale nel pbxproj, come fatto finora da questo ambiente senza Mac).
- Le tastiere **non possono** leggere il bundle id dell'app host (API pubblica) — il tono per-app usa i trait del campo di testo, non cambiarlo in un lookup del bundle id.
- `SharedContainer` e `NetworkGuard` hanno guard `#if canImport` per il build Linux: mantenerli quando si tocca quel codice.
- Il flush del safety buffer salta i campioni purgati dallo stream (gap, non duplicazione) — è una scelta deliberata, documentata in ARCHITECTURE.md.
- I test XCTest esistenti di V1 (`TranscriptStoreTests` ecc.) hanno metodi senza prefisso `test` e quindi non girano: bug preesistente, da sistemare quando si tocca quel file.
- Le tre note vocali di contesto: l'utente (Marco) usa un iPhone Air (A19 Pro, 12GB, Action Button, Dynamic Island), parla italiano e inglese, e il target di qualità dichiarato è "feeling migliore di Wispr Flow".
