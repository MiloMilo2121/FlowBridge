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
