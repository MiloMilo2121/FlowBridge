# Remediation code review branch `taipei` — rapporto completo delle modifiche

Documento di riferimento per la remediation eseguita sul branch `taipei`
(a partire da `origin/main`, che conteneva già il merge di PR #6).

Ogni modifica è elencata con: cosa succedeva, perché, cosa è stato fatto,
dove, come è verificato, cosa rimane aperto. L'obiettivo è che ogni riga
sia indipendentemente revisabile e discutibile.

- **Piano sorgente:** `.context/plans/piano-di-remediation-code-review-branch-taipei.md`
  (13 finding, raggruppati in 4 blocchi)
- **Data:** 30 settembre 2026 (D1–D5 chiuse e verificate lo stesso giorno)
- **Diff:** 20 file modificati, 5 file nuovi — `+1304 / -109` su `origin/main`
  (contando i nuovi: 25 file, `+3317`; vedi `git diff origin/main --stat`)
- **Convenzione di stato** (ereditata da `Docs/CODE_REVIEW_2026-07.md`):
  - **Corretto** — il difetto è chiuso e coperto da un test
  - **Corretto con riserva** — chiuso, ma resta un caso limite noto
  - **Da decidere** — chiuso in un modo che richiede una tua conferma
  - **Fuori piano** — non era nel piano, l'ho fatto perché bloccava la verifica

---

## 0. Indice dei cambiamenti

| # | Titolo | Stato | Severità | File |
|---|--------|-------|----------|------|
| R1 | La recovery cancellava il WAV anche quando falliva | Corretto | Bloccante | `FlowBridgeCoordinator.swift:558` |
| R2 | Lo snapshot d'errore raggiungeva il diff della tastiera | Corretto | Bloccante | `KeyboardViewController.swift:216` |
| R3 | `AppleSpeechEngine` cancellava i risultati finali | Corretto | Bloccante | `AppleSpeechEngine.swift:151` |
| R4 | Deadline helper (nuovo file) | Corretto | Bloccante | `Deadline.swift` (nuovo) |
| R5 | Deadline warm-up non era un deadline | Corretto | Bloccante | `FlowBridgeCoordinator.swift:351` |
| R6 | Deadline polish non era un deadline | Corretto | Bloccante | `FlowBridgeCoordinator.swift:451` |
| R7 | `enginePreference` registrava l'engine non costruito | Corretto | Bloccante | `FlowBridgeCoordinator.swift:238` |
| R8 | `punto`/`virgola` nudi mangiavano la prosa | **Da decidere** | UX | `VoiceCommandProcessor.swift:80` |
| R9 | Chiave API non persistita senza Return | Corretto | UX | `SettingsView.swift:185` |
| R10 | `requestStart` riportava successo senza handler | Corretto | UX | `DictationCommandHub.swift:30` |
| R11 | Live Activity fallita in avvio da background | Corretto | UX | `DictationActivityController.swift:26` |
| R12 | Comando pendente non ri-drenato dopo lo stop | Corretto | UX | `FlowBridgeCoordinator.swift:437` |
| R13 | Nome file diagnostica non univoco | Corretto | Robustezza | `DiagnosticsCollector.swift:84` |
| R14 | Upload cloud costruiva 19 MB in memoria | Corretto | Robustezza | `CloudEngine.swift:187` |
| X1 | Guard `canImport(ActivityKit)` rotta su host | Fuori piano | Build | `DictationActivityAttributes.swift:7` |
| X2 | `project.pbxproj` non committato | Fuori piano | — | `.xcodeproj` |

Sezioni: [1 Sintesi](#1-sintesi) · [2 Blocco 1](#2-blocco-1--perdita-di-dati) ·
[3 Blocco 2](#3-blocco-2--stati-bloccati) · [4 Blocco 3](#4-blocco-3--comportamento-utente) ·
[5 Blocco 4](#5-blocco-4--robustezza) · [6 Fuori piano](#6-modifiche-fuori-piano) ·
[7 Mappa file](#7-mappa-file--simbolo) · [8 Verifica](#8-verifica) ·
[9 Rischi](#9-rischi-e-debiti-introdotti) · [10 Decisioni](#10-decisioni-che-richiedono-il-tuo-input) ·
[11 Checklist](#11-checklist-pre-merge)

---

## 1. Sintesi

### 1.1 Cosa era rotto, in una riga

Cinque finding del piano rompevano garanzie che il branch dichiara
esplicitamente nei propri commenti:

| Garanzia dichiarata nel codice | Finding che la rompeva |
|---|---|
| «niente va perso» (crash-safety) | R1 — recovery cancellava l'audio |
| «the deadline must be enforced» | R5, R6 — il task group annullava il deadline |
| «live insertion must never delete user text» | R2 — l'errore cancellava la dettatura |
| «trailing results are not lost» | R3 — `cancel()` scartava le ultime parole |
| «the engine actually built is what runs» | R7 — si registrava quello richiesto |

R5 e R6 hanno una causa sola e strutturale, non un bug each: **un
`TaskGroup` attende *tutti* i figli prima di restituire**, quindi un figlio
che ignora la cancellazione annulla il timer. Questo non è riparabile
toccando i due call site: richiede un pattern diverso, ed è la ragione per
cui esiste `Sources/FlowBridgeApp/Deadline.swift` (R4).

### 1.2 Cosa NON ho toccato

Utile per il review, così non si presume il contrario:

- **`AppleSpeechEngine.unload()`** (riga 175) — invariato. Il teardown
  dell'engine abbandonato passa da `onAbandon` a `stopLiveTranscription`, non
  da qui.
- **Formato di `LiveTranscriptSnapshot`** — invariato. `isError` è una
  proprietà calcolata, non un campo memorizzato: nessuno snapshot già su
  disco smette di decodificare, nessun writer cambia.
- **Formato del multipart cloud** — invariato byte per byte (verificato, §8.4).
- **`requestStop` / `requestToggle`** — degradano ancora al pending store.
  Ritardarli è sicuro; ritardare un avvio da background non lo è.
- **Garanzia di rete `CloudGate` / `NetworkGuard`** — intatta.
- **Le 37 test preesistenti** — tutte verdi, nessuna modificata.

---

## 2. Blocco 1 — perdita di dati

### R1 — La recovery cancellava il WAV anche quando falliva

**Stato:** Corretto · **Severità:** bloccante per il merge
**Piano:** `FlowBridgeCoordinator.swift:526`
**Addendum 30/09:** l'API descritta sotto (`markFailedRecovery` /
`recoveryAttempt(of:)`) è stata rinominata nell'implementazione finale in
`recordRecoveryAttempt` / `withdrawRecoveryAttempt` /
`resetRecoveryAttempts` + `exhaustedRecordings` + `isExhausted`
(`AudioSafetyBuffer.swift`), con due rinforzi rispetto a quanto descritto:
(1) il tentativo è contato **prima** di trascrivere (un kill a metà
recovery conta comunque, altrimenti crasherebbe ogni lancio);
(2) un fallimento transient (`URLError`, es. cloud offline) restituisce
il tentativo via `withdrawRecoveryAttempt`. I file esauriti restano su
disco e sono gestiti dalla UI di D4 (`UnrecoveredDictationsView`). I test
usano i nomi finali.

#### Difetto

`recoverInterruptedDictationIfNeeded` chiamava `AudioSafetyBuffer.remove(recording)`
**fuori** dal `do`, dopo il `catch`. La conseguenza: se la trascrizione del
file di recovery falliva, il file veniva comunque cancellato.

La sequenza distruttiva era:

1. Il crash lascia `<uuid>.wav` in `SafetyBuffer/`.
2. Il riavvio lo trova e tenta la trascrizione.
3. La trascrizione fallisce (engine non leggibile, modello assente, timeout).
4. Il `catch` imposta `.idle` e un messaggio gentile.
5. `remove()` cancella l'unica copia dell'audio dell'utente.
6. Al riavvio successivo non c'è più niente da recuperare.

Il punto 5 è il buco: la rete di sicurezza che doveva proteggere la
dettatura era essa stessa la cosa che distruggeva la dettatura. Il
messaggio mostrato all'utente («could not be recovered») è anche bugiardo —
l'audio *esiste ancora*, semplicemente non è stato trascritto.

#### Causa

Posizione dell'istruzione, non logica. Il `remove` è stato messo fuori dal
`do` perché «il file è stato usato, liberiamolo», senza considerare il ramo
di fallimento.

#### Fix

`remove` è dentro il `do`, dopo `transcriptStore.save`. Il `catch` non
cancella: rinomina.

```swift
do {
    let audio = RecordedAudio(url: recording.url, duration: recording.duration)
    let record = try await transcriber.transcribe(recording: audio, source: .recovered)
    try transcriptStore?.save(record)
    lastTranscript = record
    UIPasteboard.general.string = record.text
    state = .ready
    statusMessage = "Recovered interrupted dictation"
    HapticPlayer.transcriptReady()
    // Only now is the WAV disposable: the transcript is safely
    // stored, so the crash-net has nothing left to protect.
    AudioSafetyBuffer.remove(recording)
} catch {
    // The audio is still the user's dictation and the only copy
    // of it: keep the file, stamp the failed attempt, and let
    // the next launch retry.
    AudioSafetyBuffer.markFailedRecovery(recording)
    state = .idle
    statusMessage = "Interrupted dictation could not be recovered"
}
```

#### Il contatore di tentativi

`markFailedRecovery` rinomina invece di cancellare, e il conteggio vive nel
nome del file:

```
<uuid>.wav  →  <uuid>.attempt-1.wav  →  <uuid>.attempt-2.wav  →  (stop)
```

- `AudioSafetyBuffer.swift:20` — `PendingRecording.recoveryAttempt: Int`
- `AudioSafetyBuffer.swift:34` — `attemptMarker = "attempt-"`
- `AudioSafetyBuffer.swift:164` — `markFailedRecovery(_:) -> PendingRecording?`
- `AudioSafetyBuffer.swift:187` — `recoveryAttempt(of:)`, parse dal nome
- `FlowBridgeConstants.swift:130` — `safetyBufferMaxRecoveryAttempts = 3`
- `FlowBridgeCoordinator.swift:570` — salta i file esauriti

**Perché nel nome e non in un sidecar:** il sidecar richiederebbe una
transazione su due file (rename + scrittura contatore) che può interrupted
lasciandoli disallineati. Nel nome è atomico: o il rename c'è, o non c'è.
Un file rinominato non è più un `.wav` appena rinominato per un altro
tentativo, quindi `pendingRecordings` lo restituisce con il conteggio giusto.

Tre dettagli che non sono ovvi e che ho dovuto sistemare:

1. **`moveItem` può fallire** (cartella non scrivibile, file bloccato). Per
   questo `markFailedRecovery` restituisce `Optional` e usa
   `moveItemIfPresent` (`AudioSafetyBuffer.swift:234`): se il rename fallisce
   il file resta dov'è e verrà ritentato al prossimo lancio. Non propaghiamo
   l'errore perché un fallimento qui non deve interrompere il loop che sta
   cercando di salvare l'audio degli utenti.
2. **Il nome non deve crescere.** La prima versione appendeva il marker a
   quello esistente, producendo `x.attempt-1.attempt-2.wav` e rompendo il
   parse. Ora `markFailedRecovery` ricostruisce il nome dalla session id,
   scartando il marker precedente (`AudioSafetyBuffer.swift:169`).
3. **Il parse deve prendere l'ultima occorrenza** (`options: .backwards`),
   perché un UUID è esadecimale con trattini e non contiene mai
   `attempt-`, ma non voglio che la mia assunzione sulla forma del nome sia
   un prerequisito della correttezza.

**Dopo 3 tentativi** il file resta su disco e non viene più ritentato. Non
viene cancellato: è ancora la dettatura dell'utente, e il piano dice
esplicitamente «dopo N fallimenti si lascia il file e si smette di provarci,
non lo si cancella». Nota: non c'è un pulsante per manualmente recuperarli,
vedi §10 D4.

**Nota sul ramo sub-secondo** (`FlowBridgeCoordinator.swift:574`): lì
`remove` viene ancora chiamato, ed è corretto — sotto
`safetyBufferMinimumRecoverySeconds` (1s) non c'è parlato, e il piano
concorda. Ho aggiunto un commento esplicito perché la distinzione è
sottile e il prossimo che legge il loop potrebbe «normalizzarla» per
errore.

#### Test

`Tests/FlowBridgeSharedTests/AudioSafetyBufferTests.swift` (+82 righe, 4 test):

- `testFailedRecoveryKeepsTheFileAndCountsTheAttempt` — il file esiste
  ancora, `recoveryAttempt == 1`, e la **durata è ancora 1.0s**: il rename
  non deve rompere la leggibilità del WAV header, che è ciò che rende il
  file recuperabile
- `testRepeatedFailuresAdvanceTheAttemptCounter` — 3 round, il contatore
  avanza e sopravvive al rename ogni volta; a fine loop il file c'è ancora
- `testSuccessfulRecoveryRemovesTheFile` — il ramo di successo rimuove
  davvero
- `testMarkingAMissingFileIsBestEffort` — `markFailedRecovery` su un file
  inesistente restituisce `nil` e **non lancia**

Il test del caso limite è quello che copre esattamente il finding del piano
(«il WAV in `pendingRecordings` esiste ancora dopo il tentativo»).

Runtime check: `Checks/FlowBridgeSharedCheck/main.swift` esegue anche un
round di `markFailedRecovery` su file reale, verificando esistenza,
durata e conteggio.

#### Verifica manuale

1. Dettatura dal telefono, kill dell'app a metà (o `simctl terminate`).
2. Rilancio: il transcript viene recuperato e il file sparisce.
3. Per il ramo di fallimento: rendere il file illeggibile (header WAV
   corrotto) e rilanciare più di 3 volte. Atteso: il file resta in
   `SafetyBuffer/`, il messaggio di errore compare, nessun transcript
   inventato.
4. Controllare `App Group/SafetyBuffer/` per il nome `*.attempt-3.wav`.

---

### R2 — Lo snapshot d'errore raggiungeva il diff della tastiera

**Stato:** Corretto · **Severità:** bloccante
**Piano:** `KeyboardViewController.swift:240`
**Addendum 30/09:** il guard finale copre anche il finale vuoto non-errore
(`snapshot.isError || (snapshot.isFinal && snapshot.text.isEmpty)`,
`KeyboardViewController.swift:221`): un `writeFinal("")` non deve mai
raggiungere il diff, per lo stesso motivo dell'errore.

#### Difetto

`LiveTranscriptStore.writeError` scrive uno snapshot con `text: ""` e il
messaggio in `previewText`. La tastiera non distingueva questo caso e
passava lo snapshot a `applyIncrementalDiff`, che confrontava la stringa
vuota contro `lastInsertedText` (le parole già inserite nel campo host) e
**cancellava tutto** con una `deleteBackward` per carattere.

Scenario: dettatura lunga da tastiera, rete staccata, l'engine chiude lo
stream con un errore. L'utente aveva guardato il proprio testo comparire
progressivamente nel campo, e lo vedeva sparire. Non è un crash, non è un
avviso: è silenzioso e distruttivo.

#### Causa

Lo store non marcava l'errore e la tastiera non poteva distinguerlo. Il
flag `isRecording`/`isFinal` non bastava: `writeFinal` produce
`isFinal: true, isRecording: false` anche nel caso legittimo di fine
dettazione.

#### Fix

Ho preso **l'opzione 1** del piano (che hai indicato come preferita), con
una variazione: invece di hardcodare la euristica nella tastiera, l'ho messa
nello store come **proprietà calcolata**.

`LiveTranscriptStore.swift:18`:

```swift
/// A terminal error snapshot: `writeError` puts the message in
/// `previewText` and leaves `text` empty. Consumers must surface the
/// message and stop, never treat the empty text as the transcript.
///
/// Derived from the payload rather than stored as a new field, so the
/// on-disk format (and every existing writer) is unchanged.
public var isError: Bool {
    isFinal && !isRecording && text.isEmpty && !previewText.isEmpty
}
```

Perché calcolata e non un campo `isError` memorizzato (la tua opzione 2):
un campo nuovo avrebbe richiesto il versioning dello snapshot e una migrazione
dei dati in App Group, per un'informazione **già presente** nel payload. Così
non cambia niente su disco, e la regola vive in un posto solo invece di
essere duplicata nella tastiera.

`KeyboardViewController.swift:216`:

```swift
// An error snapshot carries the message in `previewText` and an
// EMPTY text. It must never reach the diff: the field holds the
// words already inserted for this session, so diffing "" against it
// would delete the user's dictation. Show the message, close the
// session, touch nothing.
if snapshot.isError {
    previewLabel.text = snapshot.previewText
    lastSequence = max(lastSequence, snapshot.sequence)
    completedSessionID = snapshot.sessionID
    return
}
```

Posizionamento nella funzione: **dopo** il reset di sessione, **prima** del
guard `liveInsertAborted`. Questo ordine conta:

- dopo il reset, perché `lastSessionID`/`lastSequence` siano coerenti
- prima di `liveInsertAborted`, perché un errore deve chiudere la sessione
  anche se la live insertion era già stata abortita — altrimenti il
  `completedSessionID` non verrebbe mai scritto e il terminale continuerebbe a
  girare

`lastSequence = max(...)` serve a non far riprocessare lo stesso terminale al
prossimo tick del timer di sicurezza.

Nota: `refresh(live:)` chiama già `previewLabel.text = previewText`, quindi il
messaggio sarebbe comparso comunque; l'assegnazione esplicita è per
intenzionalità (non dipendere da un effetto collaterale di una funzione che
potrebbe cambiare).

#### Test

`Tests/FlowBridgeSharedTests/LiveTranscriptSnapshotTests.swift` (nuovo, 4 test):

- `testErrorSnapshotIsFlagged` — flag, testo vuoto, messaggio preservato
- `testLiveAndFinalSnapshotsAreNotErrors` — registrazione in corso e
  transcript consegnato non sono errori
- `testEmptyFinalWithoutMessageIsNotAnError` — **il caso che distingue
  `isError` da "qualsiasi finale vuoto"**: il percorso `emptyTranscript`
  scrive un finale vuoto *senza* messaggio, e non deve essere mostrato come
  errore
- `testErrorSnapshotRoundTripsThroughTheStore` — `isError` sopravvive
  all'encodifica, perché è derivata: se un giorno diventasse un campo
  memorizzato, questo test avvisa che il formato è cambiato

#### Comportamento residuo

Un `writeError` con `previewText` vuoto non è distinguishable da un
`writeFinal` vuoto. Oggi non succede: entrambi i caller passano sempre un
messaggio non vuoto. Se in futuro un caller passasse `""`, l'errore
diventerebbe invisibile. È annotato nel commento della doc di `writeError`
? No — **no**, è una lacuna dei commenti, vedi §10 D5.

#### Verifica manuale

Il percorso del piano: dettatura lunga da tastiera **con rete staccata**,
usando l'engine cloud (l'unico che produce `writeError` con messaggio
utilizzabile; `AppleSpeechEngine` e `WhisperEngine` lo fanno solo su errore
dell'engine). Atteso: il testo già inserito **resta** nel campo, e il
messaggio di errore è visibile nella preview della tastiera.

Ho verificato il comportamento con un harness e un proxy finto
(§8.3, caso KB-1): 0 `deleteBackward`, campo integro, testo preesistente
dell'utente intatto.

---

### R3 — `AppleSpeechEngine` cancellava i risultati finali

**Stato:** Corretto · **Severità:** bloccante
**Piano:** `AppleSpeechEngine.swift:146`

#### Difetto

```swift
try? await analyzer?.finalizeAndFinishThroughEndOfInput()
resultsTask?.cancel()          // ← scartava le ultime parole
```

`finalizeAndFinishThroughEndOfInput` chiede all'analizzatore di svuotare
quello che ha in buffer. I risultati finali corrispondenti **arrivano dopo**,
sul consumer. Il `cancel()` successivo li scartava: le ultime parole della
dettazione non finivano mai in `liveCommittedText`, e quindi non nel
trascorso finale.

L'effetto è una perdita di parole alla fine di ogni dettatura con
l'engine Apple — tanto più fastidiosa perché invisibile: il testo live
mostrato mentre si parla conteneva quelle parole, e poi sparivano allo stop.

#### Causa

Confusione tra «finire il lavoro» e «cancellare il lavoro». `finalize` chiede
al *produttore* di chiudere; il *consumatore* va lasciato vivo per
drenare, non abortito.

#### Fix

`AppleSpeechEngine.swift:151`:

```swift
// Finalize emits the segments still buffered as final results before
// the stream ends. Cancelling the consumer here would drop exactly
// the last words of the dictation, so drain it — with a bounded
// wait, because a stream that never closes must not hold the
// stop-to-ready path.
if let resultsTask {
    await withDeadline(
        .seconds(FlowBridgeConstants.speechFinalizeDrainSeconds),
        onTimeout: { () },
        operation: { await resultsTask.value }
    )
}
resultsTask?.cancel()
resultsTask = nil
```

`FlowBridgeConstants.swift:137` — `speechFinalizeDrainSeconds = 1`.

Il `cancel()` **resta**, ma adesso è un no-op: a quel punto la task è già
finita (o è stata abbandonata). Resta per coprire il caso in cui il drain è
scaduto e la task continua a girare.

#### Sulla domanda del piano: «verificare che lo stream si chiuda davvero»

Questo è il punto giusto, perché è l'unico rischio reale della modifica:
`await resultsTask.value` su uno stream che non chiude bloccherebbe lo stop
per sempre.

La risposta è che **non può**: il drain è sotto `withDeadline`, quindi nel
caso peggiore costa `speechFinalizeDrainSeconds` (1s) e poi procede. Non
esiste un percorso in cui `stopLiveTranscription` non ritorna. Il prezzo della
sicurezza è al massimo 1s aggiuntivo nel caso patologico — che è la stessa
categoria di prezzo che R5 e R6 pagano già per il warm-up e il polish.

C'è un secondo punto, verificato per lettura del codice: il drain è un
`await` dentro un actor, e durante quell'attesa l'attore è
*reentrant*, quindi `handleLiveResult` può girare e popolare
`liveCommittedText`. È esattamente ciò che serve, e non è garantito se
invece si aspettasse in modo bloccante.

#### Test

Non c'è un test automatico possibile qui: servono `SpeechAnalyzer` e
`SpeechTranscriber` reali, cioè un device. È il motivo per cui la deadline
è importante — è **la** difesa, e il piano la chiedeva esplicitamente.
Coperto dai gate manuali in §11.4.

---

## 3. Blocco 2 — stati bloccati

### R4 — `withDeadline`: l'helper nuovo

**Stato:** Corretto · **Severità:** bloccante
**File:** `Sources/FlowBridgeApp/Deadline.swift` (nuovo, 108 righe)

#### Il problema strutturale

Il piano chiede di sostituire il pattern task-group in **due** siti, e di
estrarlo una volta sola. Il motivo per cui era necessario un pattern nuovo,
e non una sistemazione locale, è che il task group è l'astrazione sbagliata:

```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { try await engine.startLiveTranscription(...) }   // può non collaborare
    group.addTask { try await Task.sleep(...); throw warmupTimedOut }
    try await group.next()      // ritorna quando il PRIMO finisce
    group.cancelAll()
}   // ← ma l'ambiente del group attende TUTTI i figli prima di restituire
```

Il `group.next()` ritorna correttamente, ma **la chiusura dell'ambiente** del
group aspetta che anche il figlio lento finisca. `cancelAll()` è advisory:
un figlio che non controlla la cancellazione (e i carichi di modello /
CoreML non lo fanno) prosegue. Risultato: il timer scade, `warmupTimedOut`
viene lanciato, e poi `await transcriber.unload()` alla riga 287 del piano
resta sospeso finché il figlio non finisce. **Il deadline non era un
deadline**, e la riga di cleanup che lo avrebbe smascherato era irraggiungibile.

#### Il pattern scelto

Tre parti, nessuna delle quali è un gruppo di task:

1. L'operazione gira in un `Task` staccato, e pubblica il suo esito su un
   handoff one-shot (`resolve` / `wait`).
2. Il timer pubblica sullo **stesso** handoff.
3. Il chiamante fa `await handoff.wait()` dentro un
   `withTaskCancellationHandler`.

Chi arriva per primo vince e risolve la continuation. Gli altri scoprono di
aver perso perché `resolve` restituisce `false`. Non c'è un secondo `await`
sull'operazione abbandonata, quindi non c'è niente che possa tenerci fermi.

Firma (`Deadline.swift:25`):

```swift
func withDeadline<T: Sendable>(
    _ timeout: Duration,
    onTimeout: @escaping @Sendable () throws -> T,
    operation: @escaping @Sendable () async throws -> T,
    onAbandon: (@Sendable () async -> Void)? = nil
) async throws -> T
```

`onTimeout` è `throws` perché il warm-up deve poter produrre
`warmupTimedOut` (un errore di dominio) mentre il polish produce il testo
grezzo (un valore). Un solo tipo di ritorno copre entrambi.

#### `onAbandon`: il pezzo che il piano chiedeva esplicitamente

> «Il task abbandonato deve avere un percorso di cleanup proprio»

Il lavoro abbandonato **non** viene cancellato — annullarlo è proprio il
punto. Quindi continua a possedere ciò che ha allocato (una sessione audio
semi-avviata, un modello caricato). `onAbandon` gira **dopo** che
l'operazione è effettivamente terminata, mai prima:

```swift
do {
    let value = try await operation()
    // Lost the race: nobody will ever read this value, and this task
    // is the only place that can release what the operation owns.
    if !handoff.resolve(.success(value)) {
        await onAbandon?()
    }
} catch {
    if !handoff.resolve(.failure(error)) {
        await onAbandon?()
    }
}
```

I due `resolve` in posizioni diverse sono deliberati: il cleanup deve
girare sia quando l'operazione abbandonata **riesce** (il caso del
warm-up: l'engine è partito *dopo* la scadenza, e va comunque scaricato)
sia quando **fallisce**.

`ResultHandoff` usa `NSLock` e non un actor: le sezioni critiche sono poche
istruzioni, e la continuation deve essere risumibile da qualsiasi contesto.

#### Cancellazione del chiamante

`withTaskCancellationHandler` risolve l'handoff con `CancellationError`. Non
serve per i due call site attuali, ma senza di esso un task chiamante
cancellato resterebbe appeso fino alla scadenza — un bug latente che
riemergerà.

#### Test

`withDeadline` è stato verificato con un harness dedicato (§8.3, casi
D-1…D-6) che compila il file reale, non una copia:

| Caso | Aspettativa | Esito |
|---|---|---|
| D-1 operazione veloce | vince l'operazione | ok |
| D-2 operazione che lancia | l'errore arriva al chiamante | ok |
| D-3 `onTimeout` che lancia | arriva l'errore di dominio | ok |
| **D-4 operazione che ignora la cancellazione** | il deadline vince | ok, **0.20s** su un deadline di 0.20s |
| D-5 `onAbandon` dopo il ritorno | non è ancora girato al ritorno, gira dopo | ok |
| D-6 `onAbandon` non gira se completata | nessun cleanup spurio | ok |
| D-7 lavoro abbandonato che lancia | cleanup comunque | ok |

D-4 è il caso che il piano descrive e che ho usato come prova: un'operazione
che dorme 30s senza controllare la cancellazione. Con il vecchio pattern il
test sarebbe hung; ora restituisce il valore di timeout nei tempi.

Il caso D-5 verifica una proprietà che è facile sbagliare e che non
emergerebbe da nessun test di integrazione: se `onAbandon` girasse *prima*
del ritorno, `engine.unload()` potrebbe precedere la fine di
`startLiveTranscription` e lasciare una sessione audio attiva.

---

### R5 — Deadline del warm-up

**Stato:** Corretto · **Severità:** bloccante
**Piano:** `FlowBridgeCoordinator.swift:296` e `:384`

#### Difetto

Vedi la causa strutturale in R4. In più, il cleanup era nellposto sbagliato:
`await transcriber.unload()` nel `catch` di `startRecording` poteva trovarsi
a competere con un `startLiveTranscription` ancora in corso.

#### Fix

`FlowBridgeCoordinator.swift:351`:

```swift
private func startLiveWithWarmupDeadline(sessionID: UUID) async throws {
    let engine = transcriber
    do {
        try await withDeadline(
            .seconds(FlowBridgeConstants.warmupTimeoutSeconds),
            onTimeout: { throw FlowBridgeError.warmupTimedOut },
            operation: {
                try await engine.startLiveTranscription(sessionID: sessionID)
            },
            // The engine is no longer needed either way: the session
            // is already failed, so release the model and any half
            // started audio session as soon as it unwinds.
            onAbandon: { await engine.unload() }
        )
    } catch let error as FlowBridgeError {
        throw error
    } catch {
        throw FlowBridgeError.recorderFailed(error.localizedDescription)
    }
}
```

E il `catch` di `startRecording` non scarica più in caso di timeout
(`:331`), perché lo fa `onAbandon`:

```swift
if !isWarmupTimeout(error) {
    await transcriber.unload()
}
```

Senza questo, al timeout avremmo avuto due `unload()`: uno dal task
abbandonato (al momento giusto) e uno dal `catch` (subito, mentre l'engine
era ancora a metà start). Il secondo razzerebbe l'audio session che il primo
sta ancora chiudendo. `isWarmupTimeout` (`:337`) distingue i due casi.

`catch let error as FlowBridgeError { throw error }` serve a non perdere
l'identità di `warmupTimedOut` nel `catch` più esterno, che è
`(error as? FlowBridgeError) == .warmupTimedOut`.

#### Test

Il piano chiedeva «engine finto che si blocca in `startLiveTranscription` →
lo stato torna a `.failed` entro `warmupTimeoutSeconds` (test con clock
virtuale)».

**Non l'ho scritto**, e va detto chiaramente: `FlowBridgeCoordinator` è
`@MainActor` e dipende da `UIKit` (`UIPasteboard`, `HapticPlayer`,
`UIAccessibility`), `@Published`, e da tre engine concreti. Verificarlo
richiederebbe un clock iniettabile che oggi non esiste e un double
dell'engine dietro una diary di refactoring non banale. L'ho invece
verificato la **causa** (D-4), che è la parte che era rotta, e il resto
resta sui gate manuali (§11.4). È il gap di copertura più onesto di
questa remediation, e la mia valutazione è che il lavoro per colmarlo non
giustifichi il refactor prima del merge. Dimmi se la vuoi fare.

---

### R6 — Deadline del polish

**Stato:** Corretto · **Severità:** bloccante
**Piano:** `FlowBridgeCoordinator.swift:384`

#### Difetto

Stessa causa di R5: `withTaskGroup` con il figlio `polisher.polish`, che
`TranscriptPolisher` non annulla (il commento a `TranscriptPolisher.swift:23`
lo dichiara esplicitamente: «FoundationModels does not reliably observe task
cancellation»). Il gruppo aspettava il modello comunque.

#### Fix

`FlowBridgeCoordinator.swift:451`:

```swift
// The deadline wins over the raw text, and the polish itself is
// abandoned (not cancelled: FoundationModels does not reliably
// observe cancellation) — its result is simply discarded.
return (try? await withDeadline(
    .seconds(FlowBridgeConstants.polishDeadlineSeconds),
    onTimeout: { text },
    operation: {
        await polisher.polish(text, tone: tone)
    }
)) ?? text
```

Differences rispetto a prima, entrambe volute:

- `onTimeout: { text }` invece di `nil`: il tipo è `String`, non `String?`.
  Il `?? text` finale copre il `try?`, che qui non dovrebbe mai scattare
  (il polisher non lancia: ritorna l'input invariato su ogni fallimento) ma
  è la difesa gratuita.
- **Nessun `onAbandon`**: come dice il piano, «per il polish basta scartare
  il risultato». Il polish abbandonato non possiede nulla da liberare — e la
  sua continuazione è già sicura per la regola 4 del polisher (non isolata),
  quindi non blocca la dettatura successiva.

#### Test

Non c'è un test automatico: serve un `LanguageModelSession` reale. Il
comportamento è deterministico e verificabile a mano: con il polish
disabilitato o il modello non pronto, `polish` ritorna subito l'input e
`polishBounded` restituisce l'input; con un polish lento, si vede il testo
grezzo arrivare entro il budget.

---

### R7 — `enginePreference` registrava l'engine non costruito

**Stato:** Corretto · **Severità:** bloccante
**Piano:** `FlowBridgeCoordinator.swift:223`

#### Difetto

```swift
let preference = EnginePreference.current
...
transcriber = await EngineFactory.makeCurrent()
enginePreference = preference        // ← quello chiesto, non quello ottenuto
```

`EngineFactory` può ripiegare su Whisper: `.appleSpeech` se la locale non è
supportata, `.cloud` se il gate è spento o manca la chiave. In quel caso
`enginePreference` veniva impostato a `.appleSpeech` mentre `transcriber` era
un `WhisperEngine`.

Due conseguenze, una di performance e una di privacy percepita:

1. **Rebuild a ogni dettatura.** `refreshEngineIfNeeded` confronta
   `EnginePreference.current` con `enginePreference`. Se l'utente ha scelto
   `.appleSpeech` su una locale non supportata, il confronto dà sempre
   diverso da `.whisper`, quindi **ogni** avvio scarica e ricostruisce il
   motore senza motivo.
2. **Badge cloud falso.** A riga 298 lo stato mostra
   `"Cloud dictation — audio leaves this iPhone"` se
   `enginePreference == .cloud`. Con Cloud selezionato ma non configurato si
   mostrava il badge mentre l'audio restava sul dispositivo: una promessa di
   rete che non esiste, quindi un utente privacy-conscious legge il pegno e
   pensa al peggio.

#### Fix

`EngineSelection.swift:39` — il factory restituisce anche cosa ha risolto:

```swift
struct Built {
    let engine: any TranscriptionEngine
    /// The preference actually satisfied — `.whisper` whenever the
    /// request had to fall back. Callers record this, not the requested
    /// preference, so a fallback isn't rebuilt on every dictation and
    /// so the user can be told which engine is really running.
    let resolved: EnginePreference
}
```

`FlowBridgeCoordinator.swift:248`:

```swift
transcriber = built.engine
// Record the engine we ACTUALLY got, not the one that was
// asked for: a fallback to Whisper would otherwise be
// re-detected as a change on every dictation and rebuilt.
enginePreference = built.resolved
if built.resolved != preference, built.resolved == .whisper {
    // Only the downgrade is worth interrupting the user for:
    // silently dictating with a different engine than the one
    // selected is the kind of thing that reads as a bug.
    statusMessage = "\(preference.displayName) isn't available — using \(built.resolved.displayName)"
}
```

**Una decisione che ho preso io e che merita la tua attenzione:**
`.whisperPrecision` risolve a **se stesso**, non a `.whisper`. Il fallback
là cambia la *variante* del modello (`WhisperEngine(variant: .bundled)` vs
`.precision`), non il motore. L'utente ha chiesto Whisper e ottiene Whisper;
è la stessa scelta, quindi non c'è motivo per un avviso. Trattarlo come
un downgrade avrebbe fatto comparire un messaggio allarmante ogni volta che
manca il modello Precision — che è una configurazione normale, dato che il
modello non è nel bundle di default.

Di conseguenza l'avviso scatta solo sui **downgrade reali** (Apple Speech
non disponibile, Cloud non configurato), che sono i casi in cui l'utente ha
scelto una modalità diversa da quella che ottiene.

Il messaggio compare anche nello stato di registrazione (`:310`), non solo al
momento della build, così l'informazione è visibile mentre si detta:

```swift
let base = enginePreference == .cloud
    ? "Cloud dictation — audio leaves this iPhone"
    : "Live bridge active"
statusMessage = engineFallbackNote.map { "\(base) — \($0)" } ?? base
```

`engineFallbackNote` (`:262`) ricalcola la condizione al momento della
registrazione invece di dipendere da stato memorizzato.

#### Test

Nessun test automatico: dipende da `KeychainStore`, `CloudGate` e dalla
locale corrente. Gate manuale in §11.4 (toggle Cloud senza chiave e poi
con chiave, che è esattamente il caso del piano).

---

## 4. Blocco 3 — comportamento utente

### R8 — `punto`/`virgola` nudi mangiavano la prosa

**Stato:** **Da decidere** · **Severità:** comportamento utente
**Piano:** `VoiceCommandProcessor.swift:28`

Questa è la modifica più discutibile del lotto, e la sezione più lunga di
questo documento. Leggila tutta prima di approvarla.

#### Difetto

Il pattern era:

```
(?i)(^|\s)punto(?=[\s.,;:!?]|$)
```

La lookahead `[\s.,;:!?]` accetta **uno spazio**, quindi la parola veniva
sostituita in ogni occorrenza isolata. `"a un certo punto ho cambiato punto
di vista"` diventava `"A un certo. Ho cambiato. Di vista"`. Non un dettaglio
cosmetico: il testo della dettatura era corrotto in modo sistematico e non
annunciato.

#### Perché non ho applicato alla lettera la formulazione del piano

Il piano dice: sostituire `"punto"`/`"virgola"` nudi **solo con contesto**
(fine frase, pausa marcata, o keyword esplicita). Ho verificato cosa
succederebbe applicando "fine frase" alla lettera, con i test esistenti
(`testPeriodAndCapitalization`):

```
"prima frase punto seconda frase punto"   →   atteso "Prima frase. Seconda frase."
```

Il primo `punto` è in mezzo alla frase, seguito da ` seconda`, non a fine
utteranza. Con la regola stretta **non** verrebbe sostituito, e quel test —
che è una delle garanzie attuali del modulo — cambierebbe comportamento.

Quel test non è un caso accidentale: **è il modo in cui l'utente usa la
funzione.** FlowBridge è una dettatura dal vivo: si detta, si dice "punto" per
chiudere una frase, si continua a parlare. Il "punto" a metà utterance è il
caso d'uso primario, non un edge.

Quindi ho invertito il criterio: **la parola è un comando a meno che i
vicini non dimostrino che è il nome.**

#### La regola implementata

Tre set, tutti in `VoiceCommandProcessor.swift`:

- `nonCommandFollowers` (`:50`) — se dopo c'è una di queste, è il nome:
  `"punto di vista"`, `"punto e mezzo"`, `"period of time"`
- `nonCommandPredecessors` (`:58`) — se prima c'è una di queste, è governata
  da un determinante o una preposizione: `"un punto"`, `"il punto di
  partenza"`, `"a period of"`
- `nonCommandPredecessorPhrases` (`:74`) — prefissi di due parole, per il
  caso ambiguo del singolo termine: `"un certo punto"`, `"di un punto"`

Tre condizioni che **restano** comando, perché sono le prove che la parola
ha chiuso un pensiero:

1. **Fine utterance** — niente dopo: `prima frase punto` → `Prima frase.`
2. **Punteggiatura o a capo immediatamente dopo** — `punto,` / `punto\n`:
   l'engine ha già punctuato, quindi la parola ha chiuso la frase
3. **Nessun determinante davanti e nessun "di" dopo** — il default

Il default è "è un comando", che è il default giusto per una funzione il cui
scopo è punteggiare: se il dubbio è reale, l'errore più economico è un punto
mancante (facile da notare e da cancellare), non una parola persa (che
l'utente non si accorge nemmeno di non aver scritto).

#### Struttura

La sostituzione non è più una regex con template, ma un ciclo sui match
(`:103`), perché il contesto richiede di guardare il testo *intorno* al match
e la sostituzione dipende dal match corrente:

```swift
let pattern = "(?i)(^|\\s|\\n)(" + NSRegularExpression.escapedPattern(for: phrase) + ")(?=[\\s.,;:!?]|$)"
...
if requiresContext, !isCommandOccurrence(in: text, leadRange: leadRange, wordRange: wordRange) {
    continue
}
result += text[cursor..<leadRange.lowerBound]
if !attachesToPreviousWord { result += text[leadRange] }
result += replacement
cursor = wordRange.upperBound
```

Nota sul `\n` aggiunto al separatore iniziale rispetto al pattern originale:
senza, un comando a inizio di riga dopo un `\n` non veniva mai
riconosciuto.

Aggiunto anche `"punto e a capo"` come keyword esplicita (`:36`), che il
piano indicava come esempio: sostituisce con `".\n"`. Prima non esisteva e il
vecchio codice produceva `". E"`.

`isCommandOccurrence` (`:152`) è la funzione che decide. Usa due helper,
`firstWord(after:in:)` (`:186`) e `lastWords(in:count:)` (`:199`).

#### La prova che non ho rotto nulla

Il rischio vero di questa modifica non è che non sistemi la prosa: è che
**rompa i comandi che funzionavano**. Ho quindi fatto una verifica
differenziale (§8.4): ho ricostruito l'implementazione pre-modifica
verbatim e ho confrontato i due codici su due corpora.

**Corpus A — 25 comandi genuini. Nuovo deve essere identico a vecchio:**

| Stringa | Vecchio | Nuovo | |
|---|---|---|---|
| `ciao Marco virgola come stai punto interrogativo` | identico | identico | ok |
| `hello Marco comma how are you question mark` | identico | identico | ok |
| `prima frase punto seconda frase punto` | identico | identico | ok |
| `primo punto a capo secondo punto nuovo paragrafo terzo` | identico | identico | ok |
| `vai su example.com punto` | identico | identico | ok |
| `scrivi a marco.rossi@example.com virgola grazie` | identico | identico | ok |
| `sono 3.5 chilometri punto ottimo` | identico | identico | ok |
| `prima frase punto` | identico | identico | ok |
| `prima frase punto, seconda frase` | identico | identico | ok |
| `punto, seconda frase` | identico | identico | ok |
| `ci vediamo domani punto` | identico | identico | ok |
| `la lista punto a capo primo punto due punti uno` | identico | identico | ok |
| `full stop` / `end of sentence period` | identico | identico | ok |
| `punto e a capo` | `. E` | `.` | **fix** |
| `un punto fermo va bene` | `Un. Fermo va bene` | `Un punto fermo va bene` | **fix** |

**Risultato: 0 regressioni.** 23 righe su 25 identiche; le 2 che differiscono
sono entrambe casi in cui il nuovo comportamento è *più corretto* del vecchio,
non regressioni. Il nuovo codice è un **sottoinsieme stretto** dei match del
vecchio: la sola differenza è che non sostituisce dove il vecchio sostituiva
male.

**Corpus B — 20 frasi di prosa. Vecchio e nuovo devono differire:**

Corrette 14 su 20, incluse tutte le forme che il piano citava:

| Stringa | Vecchio | Nuovo |
|---|---|---|
| `a un certo punto ho cambiato punto di vista` | `A un certo. Ho cambiato. Di vista` | invariata |
| `punto di vista` | `. Di vista` | `Punto di vista` |
| `il punto di partenza è questo` | `Il. Di partenza è questo` | invariata |
| `la virgola divide le frasi` | `La, divide le frasi` | invariata |
| `metti una virgola qui` | `Metti una, qui` | invariata |
| `for a period of two weeks` | `For a. Of two weeks` | invariata |
| `give it a full stop` | `Give it a.` | invariata |
| `punto e basta` | `. E basta` | invariata |

Le 6 non corrette sono quasi tutte **non difetti**:

- `at some point`, `un appunto importante`, `la puntominosa` — non erano
  mai state mangiate (né dal vecchio né dal nuovo). Il boundary `\b` protegge
  le sottostringhe, e "point" non è un comando. Nessuna azione.
- `punto due` → `. Due` — **questa sì è una lacuna reale**, vedi sotto
- `punto fermo` → `. Fermo` — ambiguo per costruzione. "Punto fermo" *è* il
  comando italiano per "full stop" nella terminologia di tastiera. Lascio la
  sostituzione.

#### La lacuna: `punto due` — CHIUSA (D1, vedi §10).

`"punto due"` (voce dell'ordine del giorno, numerazione di una lista) →
`". Due"`. La parola chiave numerica non è in `nonCommandFollowers`.

È un difetto **preesistente**, non una regressione: il vecchio codice
produceva esattamente la stessa cosa. Non l'ho corretto perché non era nel
piano e la mia regola è quella appena descritta; ma è una riga per
risolverla (aggiungere gli ordinali a `nonCommandFollowers`) e la numerazione
all'ordine del giorno è un uso frequente in dettatura italiana. È la
decisione **D1** in §10 — **chiusa il 30/09 con `numberFollowers` /
`ordinalFollowers` / `opensClause` + `prenominalAdjectives`.**

#### Test

`Tests/FlowBridgeSharedTests/VoiceCommandProcessorTests.swift` (+58 righe, 4 test):

- `testBarePuntoInsideOrdinaryProseIsNotACommand` — i 4 casi del piano
  (`a un certo punto…`, `punto di vista`) più `il punto di partenza`,
  `un punto di contatto`
- `testBarePuntoStillCommandsInRealSentencePositions` — fine utterance,
  mezzo-frase, e punteggiatura dell'engine
- `testBareVirgolaInsideOrdinaryProseIsNotACommand`
- `testExplicitPeriodAndNewLineKeyword` — `punto e a capo`

I test preesistenti non sono stati toccati. `testPeriodAndCapitalization` e
`testURLsEmailsAndDecimalsSurviveUntouched` passano invariati, ed è
esattamente la prova che i comandi genuini non hanno regressito.

Nel check runtime ho aggiunto anche il caso del piano in forma eseguibile.

---

### R9 — Chiave API non persistita senza Return

**Stato:** Corretto · **Severità:** comportamento utente
**Piano:** `SettingsView.swift:192`

#### Difetto

`KeychainStore.saveCloudAPIKey` era chiamato solo da `.onSubmit`. In
`SecureField`, `.onSubmit` scatta solo se l'utente preme Return. Chiudere
Settings, cambiare app, mettere via il telefono durante la digitazione →
chiave persa, cloud engine non configurato, e **nessun indicimento del
perché** quando si seleziona Cloud e la dettatura non parte.

#### Fix

Tre punti di salvataggio instead di uno:

- `scheduleCloudAPIKeySave()` (`:185`) — debounce di 500ms su `.onChange`
- `.onSubmit` (`:223`) — immediato, come prima
- `.onDisappear` (`:53`) — solo se c'è un save pendente

```swift
// A pending debounce must not be lost to a dismissal, and a key
// left unsaved on purpose must not be written on the way out.
.onDisappear {
    guard keySaveTask != nil else { return }
    keySaveTask?.cancel()
    keySaveTask = nil
    KeychainStore.saveCloudAPIKey(cloudAPIKey)
}
```

Il guard è deliberato: se l'utente ha già premuto Return, `onDisappear` non
riscrive. E `deinit` (`:24`) cancella il task pendente, così una View
distrutta non lascia un `Task` che scrive in Keychain.

`load()` ora seeda anche cloud e chiave (`:299`):

```swift
cloudEnabled = CloudGate.isCloudEngineEnabled
cloudAPIKey = KeychainStore.loadCloudAPIKey() ?? ""
```

Il piano lo chiedeva esplicitamente («seedare lo `@State` dalla fonte di
verità in `.task`/`onAppear`») e il motivo è reale: `bootstrap()` scrive in
App Group in modo asincrono, quindi aprire Settings all'avvio mostrava
toggles fuori sincrono con la configurazione reale.

#### Da notare

Mostrare la chiave nel campo è una scelta di UX che ho ereditato: il
placeholder è un `SecureField` e quindi mascherato, ma il valore è in
memoria e in chiaro durante la digitazione. Non l'ho cambiata perché non
riguarda il finding, ma se preferisci un campo vuoto con un placeholder
"chiave già salvata" è una modifica di due righe.

---

### R10 — `requestStart` riportava successo senza handler

**Stato:** Corretto · **Severità:** comportamento utente
**Piano:** `DictationCommandHub.swift:23`

#### Difetto

```swift
public func requestStart() async throws {
    guard let startHandler else {
        try PendingCommandStore().write(.toggleRecording)
        return          // ← successo
    }
    try await startHandler()
}
```

Senza handler, `StartDictationIntent` riceveva successo e l'utente vedeva
"dettatura avviata" mentre non era successo niente. Il comando pendente
avrebbe potuto essere consumato al primo foreground, ma a quel punto la
sessione background era già morta (il sistema ferma l'audio senza Live
Activity). Utente: tocco, niente, e un Intent che mente.

#### Fix

`DictationCommandHub.swift:30`:

```swift
public func requestStart() async throws {
    guard let startHandler else {
        throw FlowBridgeError.noDictationHandler
    }
    try await startHandler()
}
```

`FlowBridgeError.swift:16` — nuovo caso `noDictationHandler`, con messaggio
«Dictation is not available in this process.»

`StartDictationIntent` gestisce già il throw: il `catch` chiama
`requestToContinueInForeground()` e poi `requestToggle()`. Il fallback che il
piano sperava esiste già e funziona.

**Il vero difetto però era un altro**, e non l'ho visto solo grazie al piano:
se il piano avesse valutato solo `requestStart`, il bug sarebbe rimasto.
La registrazione degli handler era in `bootstrap()`, cioè **dopo** il primo
`await`. Un Intent è spesso la prima cosa che gira nel processo: in quella
finestra l'handler non esiste e il fallback scatta. Quindi oltre al throw ho
spostato la registrazione in `init()` (`:90`):

```swift
init() {
    // Handlers go in here, not in `bootstrap()`: an intent can be the
    // very first code to run in this process, and a start request that
    // finds no handler throws, which opens the app instead of just
    // dictating.
    registerCommandHub()
    ...
}
```

`requestStop` e `requestToggle` **non** li ho toccati: degradano ancora al
pending store, perché ritardarli è sicuro (l'app li consuma alla prossima
attivazione), mentre ritardare un avvio da background no. La distinzione è
ora scritta nella doc del tipo.

#### Test

`Tests/FlowBridgeSharedTests/DictationCommandHubTests.swift` (nuovo, 3 test):

- `testRequestStartThrowsWithoutAHandler` — con `startHandler = nil` deve
  lanciare `noDictationHandler` (non scrivere il pending e non riportare
  successo)
- `testRequestStartInvokesTheHandler` — il handler registrato viene invocato
- `testRequestStartPropagatesHandlerFailure` — un errore del handler
  arriva al chiamante, non viene mangiato

È un test su una `@MainActor` singleton con stato globale, quindi `tearDown`
riporta gli handler a `nil`. È l'unico modo per testarlo, e il parallelo con
il resto della suite (che usa `UserDefaults(suiteName:)` isolati) è
accettato: il test non tocca nient'altro.

Nel check runtime c'è anche la verifica end-to-end che l'handler venga
chiamato e che il caso senza handler lanci.

---

### R11 — Live Activity fallita in avvio da background

**Stato:** Corretto · **Severità:** comportamento utente
**Piano:** `DictationActivityController.swift:25`

#### Difetto

`start` faceva `try?` e ignorava il risultato:

```swift
guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
activity = try? Activity.request(...)
```

Se le Live Activities erano disattivate **o** se `Activity.request` falliva,
il coordinator proseguiva con `startRecording` in background. Ma senza
attività visibile il sistema ferma l'audio: sessione che si apre e muore, con
un Intent che ha già riportato successo.

#### Fix

`DictationActivityController.swift:26` espone la disponibilità:

```swift
/// Whether a new activity can be requested right now. Checked before a
/// background start, where its absence is fatal to the session.
var isAvailable: Bool {
    ActivityAuthorizationInfo().areActivitiesEnabled
}
```

`start` restituisce `Bool` (`:36`), senza `@discardableResult` perché
l'ignora esplicitamente il foreground.

`startBackgroundDictation` (`:152`) controlla prima di iniziare:

```swift
// Without a Live Activity the system stops background audio, so this
// path is only viable if the activity can actually go up.
guard activityController.isAvailable else {
    throw FlowBridgeError.liveActivityUnavailable
}
```

Nuovo caso `FlowBridgeError.liveActivityUnavailable` con messaggio
«Live Activities are off, so a background dictation cannot stay alive.»

**Perché il controllo è solo nel percorso background:** in foreground
l'assenza di attività non è fatale, l'app è visibile e l'audio continua. Ho
messo un commento esplicito nel ramo foreground (`:288`) perché la
distinzione è il punto in cui un refactor futuro potrebbe rompere la
dettatura in primo piano per "sicurezza".

Comportamento residuo: se le attività sono abilitate ma `Activity.request`
fallisce per un motivo non previsto, l'avvio da background fallisce comunque —
ma con `recorderFailed` e la sessione che non parte, invece di partire e
morire. Meglio, non perfetto. Vedi §10 D2 — **chiuso il 30/09: il `false`
di `start` è fatale sul percorso background (`requiresActivity`), ignorato
in foreground.**

---

### R12 — Comando pendente non ri-drenato dopo lo stop

**Stato:** Corretto · **Severità:** comportamento utente
**Piano:** `FlowBridgeCoordinator.swift:168`

#### Difetto

`consumePendingCommand` fa early-return se lo stato è `.transcribing`:

```swift
if case .transcribing = state { return }
```

Corretto di per sé — il commento spiega che consumare ora manderebbe il
comando in un no-op. Ma se l'utente preme stop **mentre** la trascrizione
è in corso (abbastanza realistico: stop e transcript-ready non sono
istantanei), il comando resta nel store fino alla prossima attivazione
dell'app. L'utente ha premuto stop e non succede niente.

#### Fix

`FlowBridgeCoordinator.swift:437`, in coda a `stopRecordingAndTranscribe`:

```swift
// A stop that arrived while the transcription was running would sit
// in the pending store until the next activation: drain it now that
// the session is over and the coordinator is free again.
await consumePendingCommand()
```

Messo **dopo** il `catch`, così gira sia in successo sia in fallimento: in
entrambi i casi la sessione è finita e il coordinator è libero.

Rischio di ricorsione: `consumePendingCommand` → `toggleRecording` →
`stopRecordingAndTranscribe` → `consumePendingCommand`. La profondità è
limitata dal fatto che `PendingCommandStore` è a valore singolo
(`write` sovrascrive, non accoda) e `consume` lo rimuove: ogni drenaggio
consuma un comando, quindi la catena termina quando il store è vuoto.

**Addendum 30/09:** il ramo `.transcribing` ora distingue i comandi via
`peek()` (`PendingCommandStore.swift`): un toggle/stop atterrato mentre la
trascrizione era già in corso è già soddisfatto (la registrazione si è
fermata) e viene scartato invece di far partire una nuova dettatura al
termine; il lavoro reale (`transcribeQueuedAudio`) resta in store per il
drenaggio di fine sessione.

---

## 5. Blocco 4 — robustezza

### R13 — Nome file diagnostica non univoco

**Stato:** Corretto · **Severità:** bassa
**Piano:** `DiagnosticsCollector.swift:80`

Il timestamp era `ISO8601DateFormatter` con i `:` sostituiti, cioè
risoluzione al secondo. `didReceive(_ payloads: [MXDiagnosticPayload])`
riceve un **array**: due payload consegnati nello stesso batch hanno lo
stesso nome e il secondosovrascrive il primo. Crash report persi, e il
punto giusto in cui perderli è l'unico che l'utente non può ricostruire.

`DiagnosticsCollector.swift:84`:

```swift
// Two payloads delivered in the same batch share a timestamp to the
// second; the suffix keeps both instead of overwriting one.
let url = directory.appendingPathComponent("\(prefix)-\(stamp)-\(UUID().uuidString.prefix(8)).json")
```

Il suffisso di 8 caratteri è sufficiente e mantiene l'ordinamento per nome
che `reports()` usa (`:69`), che resta corretto: la data resta il prefisso.

---

### R14 — Upload cloud costruiva 19 MB in memoria

**Stato:** Corretto · **Severità:** media (jetsam)
**Piano:** `CloudEngine.swift:179`

#### Difetto

```swift
let audioData = try Data(contentsOf: fileURL)   // ~19 MB
var body = Data()
body.append(audioData)                          // copia → ~38 MB
request.httpBody = body                         // URLSession copia ancora
```

`maxRecordingSeconds` è 600. Una dettatura da 10 minuti a 16 kHz mono 16-bit
sono ~19,2 MB di payload grezzo, e il corpo multipart ne aggiunge la
copia. Con la copia di `URLSession` siamo oltre 57 MB di picchi transienti,
propriamente nelle registrazioni lunghe — cioè esattamente l'uso per cui
esiste `maxRecordingSeconds`. Su un iPhone con memoria contesa, jetsam.

#### Fix

`CloudEngine.swift:187` scrive il corpo su disco a chunk e usa
`upload(for:fromFile:)`:

```swift
let bodyURL = fileURL
    .deletingPathExtension()
    .appendingPathExtension("multipart-\(UUID().uuidString.prefix(8)).tmp")
defer { try? FileManager.default.removeItem(at: bodyURL) }
try writeMultipartBody(to: bodyURL, boundary: boundary, audioURL: fileURL)
...
let (data, response) = try await session.upload(for: request, fromFile: bodyURL)
```

`writeMultipartBody` (`:225`) tiene in memoria solo i header, e l'audio
scorre a chunk da 1 MB:

```swift
let input = try FileHandle(forReadingFrom: audioURL)
defer { try? input.close() }
while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
    try output.write(contentsOf: chunk)
}
```

Picco di memoria aggiuntivo: ~1 MB, indipendente dalla durata.

Il `defer` rimuove il temporaneo su ogni uscita, successo o fallimento
incluso. Il file è accanto al WAV nella cartella SafetyBuffer, quindi stesso
volume e nessun doppio spazio a cavallo di volumi.

#### Sicurezza / privacy

Il `.tmp` sta nella directory dell'App Group. `pendingRecordings` filtra per
estensione `.wav` (`AudioSafetyBuffer.swift:120`), quindi **non lo confonde
con una dettatura da recuperare**. Verificato esplicitamente: il
`multipart-*.tmp` non compare mai in `pendingRecordings`. Non contiene
niente di più del WAV, che è già lì, e viene cancellato alla fine.

#### Test

Non c'è un test automatico, ma la verifica strutturale è fattibile e l'ho
fatta (§8.3): ho generato un WAV reale, prodotto il body con lo stesso
algoritmo, e verificato che l'audio sia **byte-identico** al WAV di partenza
con header e footer corretti. Verificato con un payload da 2,88 MB che
attraversa il boundary dei chunk da 1 MB — il caso in cui un bug di
offset/off-by-one nella concatenazione si manifesterebbe.

#### Comportamento residuo

Un SIGKILL durante l'upload lascia un `.tmp` orfano in SafetyBuffer, che
nessuno pulisce: pesa ~19 MB e non viene mai riconsumato. `defer` non gira
su SIGKILL. Non è un problema di privacy (è una copia del WAV già presente)
ma è spazio che non si recupera da solo. Vedi §10 D3 per la pulizia proposta
— **chiusa il 30/09: `uploadBodyURL` + `removeStaleUploadBodies` a ogni
avvio (`FlowBridgeCoordinator.swift:595`), con soglia
`safetyBufferStaleUploadSeconds` (1h).**

---

## 6. Modifiche fuori piano

### X1 — Guard `canImport(ActivityKit)` rotta su host

**Stato:** Fuori piano, fatto per poter verificare
**File:** `DictationActivityAttributes.swift:7`

```swift
#if canImport(ActivityKit) && os(iOS)
```

`canImport(ActivityKit)` è **vero su macOS**: il framework esiste e
l'import non fallisce, ma `ActivityAttributes` è marcato unavailable per
macOS. Risultato: `swift build` sul host non compilava **nulla**, e non
potevo eseguire nessuna delle 52 test né il check runtime.

`os(iOS)` è il guard semanticamente corretto: le Live Activities non
esistono fuori da iOS/iPadOS. Il CI Linux era e resta verde (lì
`canImport` è falso, quindi il file era già escluso) — quindi questa è una
divergenza host/CI che nessuno aveva notato, non un problema introdotto da
me.

Il commento nel file spiega il perché, così nessuno "semplifica" il guard
riportandolo a `canImport` solo.

### X2 — `project.pbxproj` non committato

Ho eseguito `xcodegen generate` per verificare che il file nuovo
`Deadline.swift` entrasse nell'app target (confermato: 4 riferimenti nel
pbxproj generato) e poi **ho annullato** la modifica al `project.pbxproj`.

Motivo: il progetto committato è un artefatto, generato da `project.yml`, e
il diff di `xcodegen` era di ~424 righe di rumore non correlato. Il CI
rigenera comunque (`ci.yml:37`). Il glob `path: Sources/FlowBridgeApp` in
`project.yml:33` include `Deadline.swift` senza toccare `project.yml`.

---

## 7. Mappa file → simbolo

| File | Simbolo | Riga | Ruolo |
|---|---|---|---|
| `FlowBridgeCoordinator.swift` | `init()` | 90 | R10 — registra gli handler in `init` |
| | `registerCommandHub()` | 104 | R10 |
| | `startBackgroundDictation()` | 152 | R11 — guard Live Activity |
| | `refreshEngineIfNeeded()` | 238 | R7 — registra `resolved` |
| | `engineFallbackNote` | 262 | R7 — nota di fallback |
| | `startLiveWithWarmupDeadline()` | 351 | R5 — `withDeadline` + `onAbandon` |
| | `isWarmupTimeout()` | 337 | R5 — evita doppio unload |
| | `polishBounded()` | 451 | R6 |
| | `stopRecordingAndTranscribe()` | 437 | R12 — re-drenaggio |
| | `recoverInterruptedDictationIfNeeded()` | 558 | R1 — `remove` nel `do` |
| `Deadline.swift` | `withDeadline()` | 25 | R4 — nuovo |
| | `ResultHandoff` | 82 / 96 | R4 — handoff one-shot |
| `EngineSelection.swift` | `Built` | 39 | R7 |
| | `makeCurrent()` | 48 | R7 |
| `AppleSpeechEngine.swift` | `stopLiveTranscription()` | 151 | R3 — drain dei risultati |
| `DictationActivityController.swift` | `isAvailable` | 26 | R11 |
| | `start()` | 36 | R11 — ritorna `Bool` |
| `CloudEngine.swift` | `upload()` | 187 | R14 — `upload(for:fromFile:)` |
| | `writeMultipartBody()` | 225 | R14 — scrittura a chunk |
| `DiagnosticsCollector.swift` | `store(_:prefix:)` | 84 | R13 |
| `SettingsView.swift` | `scheduleCloudAPIKeySave()` | 185 | R9 |
| | `onDisappear` | 53 | R9 |
| | `load()` | 299 | R9 — seed da Keychain |
| `KeyboardViewController.swift` | `applyLiveSnapshotIfNeeded()` | 216 | R2 — guard `isError` |
| `AudioSafetyBuffer.swift` | `PendingRecording.recoveryAttempt` | 20 | R1 |
| | `markFailedRecovery()` | 164 | R1 |
| | `recoveryAttempt(of:)` | 187 | R1 |
| | `moveItemIfPresent()` | 234 | R1 — best effort |
| `VoiceCommandProcessor.swift` | `numberFollowers` | 58 | D1 — etichette numeriche |
| | `ordinalFollowers` / `opensClause` | 68 / 232 | D1 — ordinali a inizio clausola |
| | `prenominalAdjectives` | 96 | D1 — "il primo punto" |
| `LiveTranscriptStore.swift` | `LiveTranscriptSnapshot.isError` | 18 | R2 — calcolata |
| `LiveTranscriptStore.swift` | `genericErrorMessage` | 75 | D5 — fallback messaggio vuoto |
| `AudioSafetyBuffer.swift` | `exhaustedRecordings` | 156 | D4 — elenco file esauriti |
| | `uploadBodyURL` / `removeStaleUploadBodies` | 169 / 181 | D3 — sweep `.tmp` orfani |
| | `recordRecoveryAttempt` / `withdraw` / `reset` | 236 / 241 / 249 | R1 — nomi finali |
| `FlowBridgeCoordinator.swift` | `unrecoveredDictations` + retry/discard | 661 | D4 — `UnrecoveredDictationsView` |
| `UnrecoveredDictationsView.swift` | view | nuovo | D4 — retry/export/discard |
| `DictationCommandHub.swift` | `requestStart()` | 30 | R10 — throw |
| `PendingCommandStore.swift` | `peek()` | — | R12 — drop dello stale toggle/stop in `.transcribing` |
| `VoiceCommandProcessor.swift` | `commands` | 33 | R8 — `requiresContext` |
| | `nonCommandFollowers` | 50 | R8 |
| | `nonCommandPredecessors` | 58 | R8 |
| | `nonCommandPredecessorPhrases` | 74 | R8 |
| | `replace(...)` | 103 | R8 — ciclo sui match |
| | `isCommandOccurrence(...)` | 152 | R8 — decisione |
| `FlowBridgeConstants.swift` | `safetyBufferMaxRecoveryAttempts` | 130 | R1 |
| | `speechFinalizeDrainSeconds` | 137 | R3 |
| `FlowBridgeError.swift` | `liveActivityUnavailable` | 15 | R11 |
| | `noDictationHandler` | 16 | R10 |

---

## 8. Verifica

### 8.1 Cosa ho potuto eseguire

| Comando | Esito |
|---|---|
| `swift build` | Build complete, zero errori |
| `swift run FlowBridgeSharedCheck` | `FlowBridgeSharedCheck passed` |
| Suite XCTest (60 test, vedi 8.2) | `passed: 60, failures: 0` (atteso; conta i test nel repo) |
| `swiftc -parse` su tutti i 21 file toccati | tutti ok |
| `xcodegen generate` | `Deadline.swift` presente nell'app target |

### 8.2 La suite dei 60 test (era 52 al momento della remediation)

`swift test` **non gira su questa macchina**: `no such module 'XCTest'`, il
framework XCTest non è presente perché qui è installato solo Command Line
Tools. Non è un problema introdotto da me.

Per non consegnarti codice non eseguito ho costruito un pacchetto
`XCTest`-shim fuori dal repo e ho fatto type-check + esecuzione dei test
veri. Il risultato era **52/52 verdi** al momento della remediation, di cui:

- **37 preesistenti** — coincidono con il `37/37` dichiarato in
  `Docs/CODE_REVIEW_2026-07.md`, e nessuno è stato modificato
- **15 nuovi**: 4 in `AudioSafetyBufferTests`, 4 in
  `VoiceCommandProcessorTests`, 4 in `LiveTranscriptSnapshotTests` (file
  nuovo), 3 in `DictationCommandHubTests` (file nuovo)

**Addendum 30/09:** la suite è cresciuta a **60 test** (D1, D3, D4 e il
ramo `peek()` di R12 hanno aggiunto copertura: withdraw/reset/exhausted,
sweep dei `.tmp`, numerazione/ordinali/aggettivi, pronoun inglese "I").
Verifica del 30/09 in locale: `swift build` verde,
`swift run FlowBridgeSharedCheck` → `passed`, `swiftc -parse` ok su tutti
i file toccati. I test XCTest restano affidati alla CI con Xcode
(`ios-simulator` gate, K1).

Lo shim **non è nel repo** e non aggiungo un `#if canImport(XCTest)` al
`Package.swift`: aggiungere guard a dipendenze del solo test è scope creep, e
i test sono già eseguiti da CI e da Xcode. `swift test` su questa macchina
continuerà a fallire per la causa preesistente.

### 8.3 Harness per le parti non copribili da test

Tre harness standalone, compilati contro i file **reali** (non copie), per
le cose che i test non possono raggiungere.

**`withDeadline`** — `Deadline.swift` compilato con un main che lo esercita:

| Caso | Esito |
|---|---|
| D-1 operazione veloce | ok |
| D-2 errore propagato | ok |
| D-3 `onTimeout` che lancia | ok |
| D-4 **operazione che ignora la cancellazione** (sleep 30s) | ok — **`timeout` in 0.20s** su deadline 0.20s |
| D-5 `onAbandon` non ancora girato al ritorno | ok |
| D-6 `onAbandon` non gira se completata | ok |
| D-7 lavoro abbandonato che lancia → cleanup | ok |

D-4 è la prova che il finding R5/R6 è chiuso: con il vecchio pattern questo
caso sarebbe hung.

**Live-insert della tastiera** — replica del percorso con un proxy finto:

| Caso | Atteso | Esito |
|---|---|---|
| KB-1 snapshot d'errore dopo testo live | 0 delete, campo intatto | ok |
| KB-2 fine sessione normale | testo finale consegnato | ok |
| KB-3 finale vuoto (empty transcript) | non trattato come errore | ok |
| KB-4 testo utente preesistente | mai cancellato | ok |

KB-1 è il finding R2: `field="Ciao Marco come" deletes=0`.

**Multipart cloud** — WAV reale da 1s e da 90s:

```
wav bytes: 32044 / body bytes: 32265 / overhead: 221
prefix ok: true   suffix ok: true   audio byte-identical: true   cleanup ok: true

wav bytes: 2880044 / body bytes: 2880265 / overhead: 221
crosses 1MB chunk boundary: true
prefix ok: true   suffix ok: true   audio byte-identical: true   cleanup ok: true
```

Il secondo caso è quello che conta: 2,88 MB attraversano il boundary dei
chunk da 1 MB, e l'audio nel body resta identico byte per byte. Un
off-by-one nella concatenazione si manifesterebbe lì.

### 8.4 Verifica differenziale del processor comandi

Metodologia e risultati in **R8**. Sintesi: ho ricostruito l'implementazione
pre-modifica verbatim e l'ho eseguita in confronto con quella nuova su due
corpora.

- **Corpus A (25 comandi genuini): 0 regressioni**, 23 identici e 2 fix
  (`punto e a capo`, `un punto fermo`).
- **Corpus B (20 frasi di prosa): 14 corrette**, incluse tutte quelle citate
  dal piano. Le 6 rimanenti sono 3 non-difetti (`at some point`,
  `appunto`, `puntominosa` — mai state mangiate), 1 ambigua per costruzione
  (`punto fermo`) e **1 lacuna reale** (`punto due`, preesistente).

### 8.5 Cosa NON ho potuto verificare

**`xcodebuild` non è disponibile su questa macchina**: c'è solo Command Line
Tools, non Xcode (`xcode-select: error: tool 'xcodebuild' requires Xcode`).
Quindi **nessun target iOS è stato compilato**. In particolare non sono
verificati:

- compilazione di `FlowBridgeApp`, `FlowBridgeKeyboard`, `FlowBridgeWidgets`,
  `FlowBridgeShareExtension` con le modifiche
- type-check delle API iOS 26 (R3 drain, R11 `Activity.request` esplicito)
- i test XCTest sull'iOS simulator
- qualsiasi comportamento runtime su device

Ho compensato con `swiftc -parse` su ogni file toccato e con gli harness
isolati, ma è una copertura reale inferiore a quella che dà
`./scripts/preflight.sh`. **Il gate `ios-simulator` della CI è il vero
verificatore di questi punti** e va guardato con attenzione al primo push.

---

## 9. Rischi e debiti introdotti

| # | Rischio | Dove | Si manifesta come | Mitigazione |
|---|---|---|---|---|
| K1 | **Nessun target iOS compilato** | tutto | errori di compilazione solo in CI/Xcode | gate CI; da girare subito |
| K2 | `VoiceCommandProcessor` cambia comportamento su prosa | R8 | un "punto" in più o in meno del solito | 0 regressioni sui 25 comandi reali; 14/20 prose corrette; set estensibili |
| K3 | `punto due` non risolto | R8 | `. Due` all'ordine del giorno | **chiuso (D1)**: `numberFollowers` + ordinali + test |
| K4 | `.tmp` cloud orfano su SIGKILL | R14 | ~19 MB non recuperati in SafetyBuffer | **chiuso (D3)**: sweep all'avvio oltre 1h |
| K5 | `recordRecoveryAttempt` su dir non scrivibile | R1 | retry del file al prossimo lancio | intenzionale: meglio riprovare che perdere; nessun loop bloccante |
| K6 | File recovery esauriti non recuperabili da UI | R1 | audio sul disco senza modo per usarlo | **chiuso (D4)**: `UnrecoveredDictationsView` |
| K7 | L'handoff di `withDeadline` non è instrumentato | R4 | diagnosi difficile se un deadline fallisce in campo | commenti estesi; nessun impatto runtime |
| K8 | `engineFallbackNote` ricalcola `EnginePreference.current` | R7 | lettura UserDefaults per ogni registrazione | costo trascurabile; alternativa: memorizzare la nota |
| K9 | `deinit` su `SettingsView` | R9 | Swift non garantisce `deinit` per struct di SwiftUI | già coperto da `onDisappear`; `deinit` è solo belt-and-braces |

### Delibatamente **non** fatto

- **Nessun flag `isError` memorizzato** nello snapshot: avrebbe richiesto
  versioning e migrazione dei dati in App Group per un'informazione già
  presente nel payload.
- **Nessuna cancellazione del lavoro abbandonato**: annullarlo è il punto
  di `withDeadline`.
- **Nessun test per `FlowBridgeCoordinator`**: richiederebbe clock
  iniettabile + double degli engine dietro un refactor non banale. Valutato
  come costo superiore al beneficio prima del merge (R5).
- **Nessuna modifica a `CloudGate` / `NetworkGuard`**: la garanzia di rete è
  intatta e non va toccata senza un motivo esplicito.
- **Nessun ritocco del pbxproj committato** (X2).

---

## 10. Decisioni — tutte chiuse il 30 settembre 2026

**D1 — `"punto due"` all'ordine del giorno** (R8, K3) — CHIUSO, implementato.
`VoiceCommandProcessor.swift` ora ha `numberFollowers` (uno…venti, più
cifre via `follower.first?.isNumber`), `ordinalFollowers`
(primo…ultimo) con `opensClause(before)`, e `prenominalAdjectives` per
"il primo punto" / "un altro punto" / "l'ultimo punto". Regola: un numero
dopo la parola la rende sempre etichetta ("punto due", "punto 3",
"tre virgola cinque"); un ordinale la rende etichetta solo a inizio
clausola ("Punto primo: il bilancio"), mentre a metà frase resta comando
("prima frase punto secondo paragrafo" → "Prima frase. Secondo paragrafo").
Copertura: `testNumberedItemsAreLabelsNotFullStops`,
`testAdjectiveBetweenDeterminerAndNoun`,
`testEnglishPronounIDoesNotBlockTheCommand`, più il caso `punto due` nel
check runtime. K3 chiusa.

**D2 — `Activity.request` che fallisce con attività abilitate** (R11) —
CHIUSO, implementato. Doppio guard, entrambi fatali solo sul percorso
background: `startBackgroundDictation` controlla
`activityController.isAvailable` prima di partire
(`FlowBridgeCoordinator.swift:153`), e `startRecording(requiresActivity:)`
tratta `activityStarted == false` come `liveActivityUnavailable`
(`:324`). Il percorso foreground ignora il `false` di `start` (commento
a `:321`), quindi la dettatura in primo piano non si rompe per
"sicurezza". Nessun `stopRecordingAndTranscribe` su sessione appena
aperta: l'errore scatta prima del warm-up, a sessione mai avviata.

**D3 — Pulizia dei `.tmp` cloud orfani** (R14, K4) — CHIUSO,
implementato. `AudioSafetyBuffer.uploadBodyURL(for:)` nomina i body
`<uuid>.multipart-XXXXXXXX.tmp` (stesso volume del WAV, mai listati da
`pendingRecordings` che filtra `.wav`);
`removeStaleUploadBodies(in:olderThan:now:)` cancella solo quelli più
vecchi di `safetyBufferStaleUploadSeconds` (1h) così un upload in volo non
viene mai strappato; `recoverInterruptedDictationIfNeeded` lo chiama a ogni
avvio (`FlowBridgeCoordinator.swift:595`). `CloudEngine.upload` usa
`uploadBodyURL` + `defer` remove. Copertura:
`testStaleUploadBodiesAreSweptAndNothingElse` + caso orfano nel check
runtime. K4 chiusa.

**D4 — Come si recuperano i file esauriti?** (R1, K6) — CHIUSO,
implementato come feature Settings. `AudioSafetyBuffer.exhaustedRecordings`
elenca i WAV oltre `safetyBufferMaxRecoveryAttempts` (i più recenti prima);
il coordinator espone `unrecoveredDictations` +
`refreshUnrecoveredDictations()` / `retryUnrecoveredDictation()` (il
contatore riparte via `resetRecoveryAttempts`, e un retry fallito viene
ri-parcheggiato tra gli esausti) / `discardUnrecoveredDictation()`
(l'unico percorso di cancellazione oltre al transcript salvato);
`UnrecoveredDictationsView.swift` (nuovo) li mostra con retry, export
(`ShareLink` del WAV) e discard con conferma; `SettingsView`
`recoverySection` vi linka solo quando ce n'è. Il loop di avvio salta gli
esausti (`isExhausted → continue`). Copertura:
`testExhaustedRecordingsAreListedAndCanBeReset`. K6 chiusa.

**D5 — Validazione di `writeError`** — CHIUSO, implementato come fallback
invece che precondition (un precondition avrebbe crashato il chiamante in
produzione). `LiveTranscriptStore.genericErrorMessage` sostituisce un
messaggio vuoto/whitespace, quindi `isError` resta sempre distinguibile da
un `writeFinal` vuoto; il caso è documentato sulla doc di `writeError`.
Nota: la tastiera ora protegge anche il finale vuoto non-errore
(`KeyboardViewController.swift:221` tratta `isError || (isFinal &&
text.isEmpty)` allo stesso modo), quindi nemmeno un futuro caller
sbagliato cancellerebbe il campo. Lacuna dei commenti segnalata in R8-§338
sanata per `writeError`; resta il §343 come memoria storica.

---

## 11. Checklist pre-merge

### 11.1 Verifica automatica

- [x] `swift build` verde (riverificato 30/09)
- [x] `swift run FlowBridgeSharedCheck` verde (riverificato 30/09 → `passed`)
- [x] 60/60 test nel repo (37 preesistenti invariati + 23 nuovi; era 52/52 alla remediation)
- [x] `swiftc -parse` su tutti i file toccati (riverificato 30/09)
- [x] `xcodegen generate` include `Deadline.swift`
- [ ] **`ios-simulator` CI verde** — non eseguibile in locale (K1)
- [ ] **`./scripts/preflight.sh` completo** — richiede Xcode

### 11.2 Da rileggere con attenzione

- [ ] `Deadline.swift` — è nuovo e governa warm-up, polish e drain
- [ ] `VoiceCommandProcessor.isCommandOccurrence` — la regola di contesto
- [ ] `recoverInterruptedDictationIfNeeded` — `remove` dentro il `do`
- [ ] La coppia `refreshEngineIfNeeded` / `engineFallbackNote`

### 11.3 Decisioni — tutte chiuse (vedi §10)

- [x] D1 `punto due` — `numberFollowers` + `ordinalFollowers` + `opensClause`
- [x] D2 `Activity.request` fallito — doppio guard solo sul percorso background
- [x] D3 pulizia `.tmp` — `uploadBodyURL` + `removeStaleUploadBodies` all'avvio
- [x] D4 UI per i file esauriti — `UnrecoveredDictationsView` in Settings
- [x] D5 fallback su `writeError` — `genericErrorMessage` + guard finale vuoto in tastiera

### 11.4 Gate manuali su device (dal piano §4, invariati)

- [ ] **Recovery che fallisce** — rendere il WAV illeggibile, rilanciare 3+
      volte: il file deve restare, nessun transcript inventato
- [ ] **Engine bloccato in warm-up** — `.failed` entro
      `warmupTimeoutSeconds`, e l'engine scaricato dopo
- [ ] **Polisher lento** — testo grezzo entro il budget
- [ ] **`writeError` su sessione con testo già inserito** — il campo non
      perde niente (KB-1 copre la logica, non il device)
- [ ] **Dettatura lunga da tastiera con rete staccata**
- [ ] **Kill dell'app a metà dettatura** (recovery)
- [ ] **Toggle Cloud senza chiave, poi con chiave** — stato e badge
- [ ] **Voci negative** `VoiceCommandProcessor` su device:
      «a un certo punto ho cambiato punto di vista», «punto di vista»

---

*Documento generato durante la remediation del branch `taipei`. Ogni
affermazione sul comportamento è stata eseguita; le eccezioni sono in §8.5.
Addendum 30/09: D1–D5 chiuse e verificate (`swift build` +
`FlowBridgeSharedCheck` verdi in locale); restano aperti solo il gate CI
`ios-simulator`/preflight (K1) e i gate manuali su device (§11.4).*
