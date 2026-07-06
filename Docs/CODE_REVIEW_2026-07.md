# Code review totale — luglio 2026

Review di tutti i moduli (app, shared, keyboard, widgets, intents) a caccia di
bug di correttezza, race e problemi di velocità/fluidità. Ogni finding indica
se è stato **corretto in questa PR** o resta **aperto** (con il perché).

## Corretti in questa PR

### C1 — Il cambio motore in Settings non aveva alcun effetto (bug funzionale)
`FlowBridgeCoordinator` creava il motore una sola volta all'init del singleton
(`let transcriber = EngineFactory.makeCurrent()`): il picker in Settings
scriveva la preferenza ma l'app continuava a usare il vecchio motore fino al
riavvio. **Fix:** `refreshEngineIfNeeded()` all'inizio di ogni dettatura —
scarica il vecchio motore e costruisce quello scelto, mai a metà sessione.

### C2 — `VoiceCommandProcessor` storpiava URL, email e decimali (bug dati)
La regex `([.,;:!?])(\p{L})` inseriva uno spazio dopo ogni punteggiatura
seguita da lettera, e la capitalizzazione scattava dopo ogni "." anche senza
spazio: "example.com" → "example. Com", "marco.rossi@…" → mangled. **Fix:**
rimossa l'inserzione di spazi (le sostituzioni dei comandi preservano già la
spaziatura) e capitalizzazione solo dopo *punteggiatura di fine frase +
whitespace*. Nuovi test per URL, email e decimali.

### C3 — Race di deallocazione in `DarwinNotificationObserver` (crash raro)
Il callback C recuperava l'istanza con `takeUnretainedValue()` dal puntatore
grezzo: una notifica in volo su un altro thread durante la deallocazione
poteva dereferenziare memoria liberata. La tastiera crea/distrugge observer a
ogni apparizione, quindi la finestra era reale. **Fix:** registry statico
protetto da `NSLock` keyed sul puntatore — il callback consulta solo il
registry e al massimo trova un entry mancante, mai memoria liberata.

### C4 — Unload del modello mentre una trascrizione era in corso (bug)
`handleScenePhase(.background)` scaricava il motore in ogni stato diverso da
`.recording`: mettere l'app in background subito dopo lo stop (stato
`.transcribing`) uccideva la trascrizione in volo. **Fix:** unload solo negli
stati idle/ready/failed; per il resto ci pensa il TTL di idle.

### C5 — Polish LLM sotto memory warning (bug di pressione memoria)
Il gestore del memory warning fermava la dettatura e la pipeline caricava
comunque il modello 3B per il polish — il contrario di liberare memoria.
**Fix:** `stopRecordingAndTranscribe(skipPolish: true)` nel percorso memory
warning: consegna il verbatim e libera.

### C6 — Latenza stop→testo non limitata (fluidità)
Il polish era sincrono e senza limiti: su testi lunghi la generazione a ~30
token/s poteva tenere l'utente in attesa 10s+. **Fix:** `polishBounded` —
testi oltre 3.500 caratteri saltano il polish (sforerebbero comunque la
finestra di contesto del modello), e un polish più lento di **4 secondi**
viene abbandonato in favore del testo grezzo. Lo stop→pronto è ora limitato
per costruzione. (Con `prewarm()` durante la registrazione, il caso tipico
resta 1–3s.)

### C7 — Spam di update alla Live Activity (fluidità/energia)
Ogni snapshot del motore (anche molti al secondo) generava un
`Activity.update` — IPC verso il processo di rendering dell'isola. **Fix:**
dedupe sul testo invariato + intervallo minimo di 0,3s tra update; i frame
scartati sono superflui perché lo snapshot successivo li sostituisce.

### C8 — Tastiera: timer mai invalidato in `deinit` (leak) + doppia decodifica
Se il VC veniva deallocato senza `viewDidDisappear`, il timer restava
schedulato per sempre sul runloop. Inoltre ogni evento decodificava lo
snapshot due volte (in `refresh()` e in `applyLiveSnapshotIfNeeded`). **Fix:**
`deinit` invalida il timer; decodifica singola passata a `refresh(live:)`;
il closure del timer asserisce l'isolamento MainActor (Swift 6).

### C9 — Hint di tono pubblicato una sola volta per apparizione
Cambiando campo nella stessa app (la tastiera non riappare) il tono restava
quello del campo precedente. **Fix:** ripubblicazione in `textDidChange` con
cache del valore (no-op se invariato, zero churn di I/O).

### C10 — Conversione campioni del safety buffer sample-per-sample (perf)
`append` costruiva la `Data` con un'append da 2 byte per campione (48k/s col
motore Apple). **Fix:** conversione bulk in un array `Int16` + una singola
`Data(buffer:)`.

## Secondo giro (review approfondita — bug corretti)

### C11 — `AppleSpeechEngine`: safety buffer avviato fire-and-forget (dati persi)
`begin(sessionID:)` girava in un `Task` non atteso mentre il tap installava
subito `Task { append(...) }`: l'ordinamento dei task sull'actor non è FIFO,
quindi `append` poteva eseguire prima di `begin` (file handle non ancora
creato → campioni scartati) e — peggio — **due `append` potevano eseguire in
ordine inverso, corrompendo l'ordine dei frame nel WAV di recovery**. **Fix:**
`begin` è ora atteso prima di installare il tap; il tap accumula i campioni in
un `SampleAccumulator` thread-safe (un produttore/un consumatore, ordinato) e
un task periodico li drena nel WAV in ordine — stesso pattern collaudato di
`WhisperEngine`.

### C12 — `AppleSpeechEngine`: sottoscrizione ai risultati dopo l'avvio audio (parole perse)
Il task che consuma `transcriber.results` veniva creato dopo `analyzer.start`
e `startCapture`: se lo stream non bufferizza, le prime parole prodotte prima
della sottoscrizione andavano perse (era il finding aperto A3). **Fix:** la
sottoscrizione ai risultati avviene ora **prima** di alimentare l'audio.

### C13 — `AppleSpeechEngine`: accumulo illimitato senza safety buffer (leak)
Introdotto e corretto nello stesso giro: se la cartella del safety buffer non
è disponibile, il tap non deve accumulare (nessuno drenerebbe). Gate esplicito
sull'accumulatore.

### C14 — `DictationActivityController`: update ActivityKit non ordinati (glitch isola)
Ogni `update/finish/end` lanciava un `Task` scollegato: due update potevano
applicarsi fuori ordine, o un update stantio poteva atterrare **dopo** che
l'activity era già terminata (era il finding aperto A5). **Fix:** tutte le
chiamate ActivityKit passano ora per una singola catena di task seriale, che
preserva l'ordine di richiesta.

### C15 — `AudioFileDurationReader`: API sincrona deprecata (durate errate)
Usava `AVAsset.duration` sincrono, deprecato da iOS 16 e che su iOS 26 può
restituire un valore indefinito (→ durata 0 nelle statistiche e sui record di
audio condiviso). **Fix:** portato ad `await asset.load(.duration)`; i due
call-site (coordinator, benchmark) erano già async.

## Terzo giro — verifica pre-Xcode (bug corretti)

Eseguita tutta la verifica automatizzabile in ambiente Linux prima del primo
build su Mac. Ha trovato quattro problemi che **anche Xcode avrebbe colpito**:

### C16 — Errore di concorrenza Swift 6 in `TranscriptStore` (build rotta)
`TranscriptStore` era un `actor` che immagazzinava un `UserDefaults`
(thread-safe ma non `Sendable`): passargli un defaults esterno da un contesto
task-isolated è un errore di data-race sotto Swift 6 strict — che il target di
test iOS avrebbe fatto fallire. **Fix:** convertito a `@unchecked Sendable
final class`, coerente coi suoi fratelli (`LiveTranscriptStore`,
`PendingCommandStore`); rimossi gli `await` ai call-site (metodi ora sincroni).
Scoperto eseguendo `swift test` (prima giravano solo i "check").

### C17 — `FlowBridgeWidgets-Info.plist` mancante (rischio xcodegen)
`project.yml` referenzia `Configuration/FlowBridgeWidgets-Info.plist` ma il
file non era stato creato. XcodeGen lo rigenera dalle properties, ma per
coerenza del repo è stato aggiunto esplicitamente.

### C18 — Test V1 senza prefisso `test` non eseguiti (era A6)
`savesAndLoadsLatestTranscript`, `collapsesWhitespaceAndPunctuationSpacing`,
`preservesEmptyText`, `consumesCommandOnce` non venivano eseguiti da XCTest.
**Fix:** prefisso `test` aggiunto; ora girano (36 test totali, tutti verdi su
Linux).

### C19 — La suite XCTest non era eseguibile in CI
Aggiunto un `.testTarget` a `Package.swift` così `swift test` esegue davvero
la suite del framework condiviso su Linux, indipendente dal target
`bundle.unit-test` iOS di `project.yml`. **36/36 test verdi.**

### Nota operativa — il progetto Xcode committato NON ha il target widgets
Verificato: `FlowBridge.xcodeproj` committato non contiene `FlowBridgeWidgets`.
**Aprire direttamente il `.xcodeproj` senza `xcodegen generate` prima** fa
mancare Live Activity/Dynamic Island. Lo script `scripts/preflight.sh`
automatizza tutto (toolchain → swift build/test → xcodegen → xcodebuild di
tutti i target per simulatore → test iOS).

## Aperti (con motivazione)

### A1 — API iOS 26 da validare in Xcode *(già tracciato in HANDOFF_NEXT_STEPS.md)*
`AppleSpeechEngine`, `TranscriptPolisher`, `DictationIntents`
(`requestToContinueInForeground`), `supplementalActivityFamilies`: scritti
contro la superficie documentata, non compilabili in questo ambiente.

### A2 — Normalizzazione O(n²) sui callback live (perf, accettata per ora)
Sia `WhisperEngine.liveText` sia `AppleSpeechEngine.handleLiveResult`
rinormalizzano l'intero testo accumulato a ogni callback: su dettature da 10
minuti il costo cresce quadraticamente (regex su ~10k char, più volte al
secondo a fine sessione). **Non corretto di proposito:** gira su un actor in
background (mai sul main thread, quindi nessuno stutter UI), e la
normalizzazione capitalizza il *primo* carattere del testo combinato —
normalizzare i pezzi singolarmente capitalizzerebbe a metà frase. Su A19 il
costo è trascurabile per lunghezze realistiche; l'ottimizzazione corretta
(prefisso confermato normalizzato una volta, capitalizzazione applicata solo
alla fine) va fatta con lo streaming reale sotto profiler.

*(Il finding A3 del primo giro — sottoscrizione ai risultati — è stato risolto
in C12.)*

### A4 — Trigger utente ignorato durante la recovery al bootstrap
Se l'utente preme l'Action Button mentre `recoverInterruptedDictationIfNeeded`
sta trascrivendo (stato `.transcribing`), il toggle viene ignorato invece di
essere accodato. Finestra piccola e comportamento sicuro; una coda comandi è
lavoro di rifinitura post-device.

### A5 — Ordering degli update ActivityKit non garantito
`DictationActivityController.update` lancia un `Task` per update; in teoria
due update potrebbero arrivare fuori ordine. Con il throttle di C7 la
probabilità è trascurabile; se su device si osservassero regressioni visive,
serializzare con un singolo task consumer.

### A6 — Test V1 senza prefisso `test` (bug preesistente, non nostro)
`TranscriptStoreTests.savesAndLoadsLatestTranscript` e simili non vengono
eseguiti da XCTest. Da sistemare quando si tocca quel file.

### A7 — Incoerenza deliberata: testo live grezzo vs consegna polished
La tastiera in live mode inserisce il testo grezzo in streaming; clipboard e
cronologia ricevono il polished. È una scelta (il polish arriva solo a fine
sessione), ma va osservata nel dogfood: se disorienta, valutare il pattern
"consegna grezzo subito, sostituisci con polished dopo".

## Note di fluidità già a posto (verificate, nessuna azione)

- Timer dell'isola con `Text(timerInterval:)`: zero budget di update.
- Tastiera: diff a prefisso comune, niente delete-all/reinsert.
- Polisher `prewarm()` durante la registrazione: niente cold start allo stop.
- Modello: un solo motore caricato, TTL di unload a 180s, `SpeechTranscriber`
  in memoria di sistema (zero footprint nostro).
- Live Activity avviata *prima* del warm-up del motore: l'isola risponde al
  click istantaneamente.
- Cronologia: JSON ≤200 record con cache in memoria; ricerca lineare — banale.

## Verifica di questa PR

- `swift build` (Linux, Swift 6.0.3): zero errori.
- `swift run FlowBridgeSharedCheck`: verde.
- Test XCTest aggiornati (nuovi casi URL/email/decimali per i comandi vocali).
- Nessun file nuovo di codice → nessuna modifica al progetto Xcode necessaria.

## Quarto giro (red-team + dead-code + fondamenta — branch `claude/v3-hardening`)

Tre agenti di analisi (dead-code, red-team, best practice di settore) hanno
prodotto i finding qui sotto; tutti quelli marcati sono stati **corretti in
questo giro**.

### Robustezza (red-team)

- **H1 — `processQueuedAudioIfNeeded` senza guardia di stato** *(corretto)*:
  poteva lanciare una trascrizione file mentre lo stream live era attivo sullo
  stesso motore (decode CoreML concorrente). Ora ritorna se lo stato non è
  idle/ready/failed, e viene ritentato quando lo stato torna gestibile.
- **H2 — Stato bloccabile in `.warming`** *(corretto)*: warm-up con deadline di
  15s (`FlowBridgeError.warmupTimedOut`), Stop/Toggle funzionano anche in
  `.warming` (`abortWarmup()` chiude l'activity e scarica il motore), e un
  warm-up completato dopo un abort viene riconosciuto e scartato
  (`warmupToken`).
- **M1 — Polish abbandonato che serializzava la dettatura successiva**
  *(corretto)*: `polish` è ora `nonisolated` — la sessione prewarmed viene
  presa dall'actor in un hop rapido, ma la generazione gira fuori
  dall'actor: un job oltre la deadline di 4s non blocca più il prewarm/polish
  della dettatura dopo.
- **M2 — Comando pending consumato-e-perso** *(corretto)*:
  `consumePendingCommand` non consuma più quando lo stato non è gestibile; il
  comando resta nello store e viene ripreso al ritorno in idle/ready/failed.
- **M3 — Session-append senza limite** *(corretto)*: cap a
  `sessionAppendMaxCharacters` (8.000): oltre, si inizia un nuovo record
  invece di appendere.
- **M4 — Thread audio realtime che allocava sotto lock** *(corretto)*:
  `SampleAccumulator` pre-riserva la capacità (dimensionata sul flush
  interval); `drain()` prepara il buffer sostitutivo fuori dal lock e fa solo
  uno `swap` dentro.
- **M5 — Lettura non sincronizzata di `audioProcessor.audioSamples`**
  *(mitigato)*: singolo snapshot con bounds ricalcolati e clampati sullo
  snapshot stesso; resta best-effort (dipende dagli internals di WhisperKit),
  coerente con la semantica gap-tollerante del safety buffer.
- **L1 — Doppio append sullo stop (Whisper)** *(corretto)*: flag
  `isFlushingSamples` + il contatore avanza solo dopo l'append; lo stop
  attende il flush in volo.
- **L3 — Memory warning in `.warming`** *(corretto)*: gestito da
  `abortWarmup()`.
- **L4 — Safety buffer segnato attivo anche se `begin()` falliva (Apple)**
  *(corretto)*: `safetyBuffer` viene impostato solo se `begin` riesce; il tap
  accumula solo se il buffer esiste.
- **L5 — Eviction cronologia che scartava il take più recente con ≥200 pin**
  *(corretto)*: l'eviction non tocca mai l'elemento appena inserito e, se
  tutto è pinnato, evicta comunque il più vecchio. Test aggiornato.
- **L6 — Share extension che lasciava copie temporanee** *(corretto)*: il file
  temp viene cancellato dopo `copyIntoInbox`.

### Dead code e semplificazione

- `FlowBridgeRecorder` → **`MicrophonePermission`**: rimosse ~65 righe di
  macchina di registrazione mai usata (registrano i motori); resta solo la
  richiesta permesso e `struct RecordedAudio`.
- `HapticPlayer.failed()` ora usato in `fail()` (prima l'aptica era
  reimplementata inline).
- `AppleSpeechEngine.isUsable()` ora usato da `EngineFactory.makeCurrent()`
  come guardia con fallback a Whisper (chiude dead code *e* un buco runtime).
- Rimosse API mai chiamate: `TranscriptStore.clear()`,
  `LiveTranscriptStore.clear()`, `TranscriptHistoryStore.clear()`,
  `VocabularyStore.replaceAll(_:)`.
- **`FlowBridgeJSON`**: un solo paio encoder/decoder `.deferredToDate`
  condiviso — eliminate 12 duplicazioni in 5 file (incluse le factory gemelle
  `PendingCommandStore.flowBridge` / `ToneContext.iso`).
- `LiveTranscriptStore.writeFinal/writeError`: tolto il magic
  `sequence: Int.max` duplicato nei motori.
- De-dup di `NetworkGuard.install()` (solo in `AppDelegate`).

### Tastiera (decisione utente: live-insert resta il default)

- **Guardia anti-desync**: prima di cancellare, la tastiera verifica che il
  contesto prima del cursore termini ancora con ciò che ha inserito
  (`fieldStillMatchesInsertedText()`, tollerante alla finestra troncata del
  proxy). Se non combacia (utente ha scritto/spostato il cursore, host ha
  auto-corretto), la sessione live viene abbandonata senza cancellare nulla.
- Nessun inserimento nei campi sicuri (`isSecureTextEntry`).

### Fondamenta (PR 4)

- **CI GitHub Actions** (`.github/workflows/ci.yml`): job Linux (build + test
  + `FlowBridgeSharedCheck` in container swift:6.0) e job macOS
  (xcodegen + `xcodebuild` per simulatore senza firma).
- **MetricKit opt-in, solo locale** (`DiagnosticsCollector`): crash/hang
  report salvati su questo iPhone, revisione e condivisione manuali in
  Settings, cancellazione totale. Nessun upload, coerente col posizionamento.
- **Accessibilità (primo pass)**: label VoiceOver su bottoni app/tastiera,
  annunci di stato ("Listening", "Transcript ready"), simboli dell'isola con
  label e variante Reduce Motion.
- **Review-readiness**: `NSSupportsLiveActivities(FrequentUpdates)`,
  `NSSpeechRecognitionUsageDescription`, usage string del microfono esplicita
  sull'on-device. I 3 stati di indisponibilità FoundationModels hanno
  spiegazioni distinte in Settings.

### Modelli (PR 5)

- **Precision = large-v3-turbo** (multilingue, deciso dall'utente):
  `WhisperModelLocator` cerca prima il bundle (`PrecisionModel` staged da
  `scripts/fetch-whisper-precision.sh` a build time), poi Application
  Support. Nessun download runtime.
- **CloudEngine opt-in (ElevenLabs Scribe), OFF di default**: registra in
  locale nel safety buffer WAV e carica solo allo stop; se l'upload fallisce
  il WAV resta per la recovery ("il transcript non si perde mai" vale anche
  qui). `CloudGate` apre il *solo* host del provider e *solo* nel processo
  app con consenso esplicito + toggle attivo; le extension restano a rete
  bloccata sempre. Chiave API in Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), mai in UserDefaults.
  Badge visibile in registrazione quando il motore è cloud.

### Verifica di questo giro

- `swift build` (Linux, Swift 6.0.3): zero errori; `swift test`: 37/37 verdi;
  `swift run FlowBridgeSharedCheck`: verde.
- pbxproj: i 5 file nuovi registrati e verificati (6 occorrenze ciascuno,
  riferimenti coerenti). `xcodegen generate` resta comunque obbligatorio al
  primo giro su Mac.
- Restano aperti A1–A7 (sopra) più la decisione pre-submit sul Full Access
  della tastiera (v. HANDOFF_NEXT_STEPS.md).
