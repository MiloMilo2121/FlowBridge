# Il contratto del diario (Mac ↔ iPhone)

Il diario è una cartella di file JSON, **uno per voce**. Lo scrivono FlowBridge per Mac e
FlowBridge per iPhone. Questo documento è il formato; le fixture in
`prove/dati/diario/` ne sono gli esempi, e le prove dei due lati le leggono:
`prove/test_contratto_diario.py` (forma, e nessun dato dei clienti) e `proveContrattoDiario` in
`ProveMotore` (il codice vero le legge, le riscrive uguali, rispetta le lapidi).

Il codice che lo implementa è `app/Sources/Diario/Diario.swift`: Foundation pura, dichiarato
anche per iOS, ed è il file che si porta nell'app iPhone
(`docs/PORTARE-IL-DIARIO-SU-IPHONE.md`).

## Le regole

1. **Un file per voce, nome = id in minuscolo**: `3f1c2a4e-….json`. Due dispositivi che
   scrivono nella stessa cartella sincronizzata non scrivono mai lo stesso file. Niente file
   indice condiviso: l'indice si ricostruisce leggendo.
2. **Una voce scritta non si riscrive.** È la regola delle trascrizioni (`AGENTS.md`): quello che
   si cita deve restare quello. Scrivere su un id esistente è un errore. La scrittura è atomica
   ed esclusiva (`renamex_np` con `RENAME_EXCL`), coordinata con `NSFileCoordinator`.
3. **Cancellare = lapide + togliere il file.** `<id>.cancellata.json` senza testo. Una voce con
   la sua lapide non si mostra, anche se ricompare da un altro dispositivo. Una lapide impedisce
   anche di riscrivere quell'id. Le **call non si cancellano** dal diario.
4. **Le call non si incorporano nel JSON.** Una voce `call` porta il titolo, la data, la durata e il percorso
   della trascrizione relativo alla radice dei dati (`testi/…txt`), **mai il testo**: l'originale
   resta evidenza nell'archivio Mac. Per leggerla su iPhone, il Mac ne crea una copia
   immutabile nello stesso percorso relativo dentro iCloud Drive; non riscrive l'originale. Il suo id si ricava dal percorso
   (`VoceDiario.call(trascrizione:…)`), così la stessa call ha lo stesso id ovunque.
5. **Si aggiungono campi, non se ne rinominano.** Un lettore ignora i campi che non conosce;
   `schema` sale solo se un campo cambia significato.

## I campi

| campo | tipo | quando c'è | cosa |
|---|---|---|---|
| `schema` | intero | sempre | oggi `1` |
| `id` | UUID (stringa) | sempre | lo stesso UUID del nome del file (nel JSON maiuscolo, come lo scrive `UUID` di Swift; nel nome minuscolo: il confronto ignora le maiuscole) |
| `quando` | ISO 8601 **con il fuso** | sempre | `2026-09-29T21:30:05+02:00`: l'ora che era lì |
| `dispositivo` | `mac` \| `iphone` | sempre | chi l'ha scritta |
| `tipo` | `dettatura` \| `call` \| `nota` | sempre | |
| `testo` | stringa | dettature e note | il testo inserito |
| `testo_grezzo` | stringa | se diverso da `testo` | il testo del riconoscimento, prima della pulizia e del vocabolario |
| `titolo` | stringa | call | |
| `pulizia` | `nessuna` \| `regole` \| `modello` | dettature | quella usata davvero |
| `cancello` | `{passato, motivi}` | dettature pulite | se la pulizia è stata rifiutata, `testo` è il grezzo (più il vocabolario) e `motivi` dice perché |
| `motore` | stringa | dettature | `dettatura+contesto`, `trascrizione`… |
| `versione_os` | stringa | dettature | i modelli di Apple cambiano con il sistema |
| `lingua` | codice | quando si sa | `it`, `en` |
| `durata_s` | numero | quando si sa | secondi di audio |
| `app` | bundle id | dettature | dove è andato il testo |
| `trascrizione` | percorso relativo | call | `testi/<nome>.txt` |

La lapide: `{schema, id, cancellata_il, dispositivo}`.

## Da FlowBridge per iPhone

`TranscriptRecord` dell'iPhone si legge in questo formato così:

| iPhone | diario |
|---|---|
| `id` | `id` |
| `text` | `testo` |
| `rawText` | `testo_grezzo` |
| `language` | `lingua` |
| `createdAt` | `quando` (con il fuso del telefono) |
| `audioDuration` | `durata_s` |
| `source` | `tipo: dettatura`, `dispositivo: iphone` |

## Dove sta la cartella

Sul Mac `~/Library/Application Support/FlowBridge/diario/` è la copia locale. Su iPhone
la copia locale è nel container dell'app. Entrambe si rispecchiano nel container
`iCloud.com.marcomilanello.flowbridge/Documents/FlowBridge/` con le sottocartelle
`diario/` e `testi/`. La sincronizzazione è eventuale: senza iCloud Drive i nuovi file
restano locali e lo stato lo segnala. Serve lo stesso Apple Account su Mac e iPhone.

## Lo specchio su iCloud

Le stesse regole sui due lati. Sul Mac: `app/Sources/Condivisione/Specchio.swift` nel repo del
trascrittore (prove in `proveCondivisione`). Qui: `Sources/FlowBridgeShared/SpecchioDiario.swift`,
provato su dati sintetici da `Checks/FlowBridgeSharedCheck/SpecchioChecks.swift`. Basta un lato
che ricarica ciò che l'altro ha cancellato per rimettere il testo sui server di iCloud a ogni sync.

1. **Si scambiano solo i nomi del contratto**: `<uuid minuscolo>.json` e
   `<uuid minuscolo>.cancellata.json`. Un altro nome che finisce in `.json` (le copie di
   conflitto di iCloud, `<id> 2.json`) si segnala e resta fuori.
2. **Prima di prendere un file lo si guarda**: un oggetto JSON con `schema` intero e `id`
   uguale al nome (senza maiuscole). Non si decodifica tutta la voce: uno schema futuro passa.
   Un file che non passa non si copia, e si riprova al giro dopo.
3. **Si scrive una volta, tutto o niente**: temporaneo nella stessa cartella, poi rename
   esclusivo. Mai copiare sul nome finale.
4. **Si legge coordinati, e solo ciò che è già scaricato**: un file di iCloud non ancora sul
   disco (o un segnaposto `.<nome>.icloud`) si chiede e si aspetta. Un segnaposto vale come file
   presente: scriverci accanto il «mancante» sarebbe un conflitto in iCloud.
5. **La lapide vince su entrambi i lati**: se c'è da una parte, si copia dall'altra e il
   `<id>.json` si toglie da tutte e due, così il testo cancellato non resta nel contenitore.
   Solo una lapide **valida** (regola 2) cancella: una rotta si segnala e non tocca niente.
6. **Le call non si cancellano.** Una lapide con l'id di una call (dalla voce; il Mac la riconosce
   anche dal percorso della trascrizione, se la voce non c'è ancora) si rinomina `<id>.cancellata.json.rifiutata` su
   ogni lato e si segnala: lasciata com'è, `voci()` nasconderebbe la call ovunque.
7. **Una voce sparita senza lapide non si ricarica.** Ogni lato tiene l'elenco delle voci che ha
   visto nel contenitore (sul Mac `diario-visti-in-icloud.json`, qui `seen-in-icloud.json`): se una sparisce
   da iCloud e la lapide non è ancora arrivata (iCloud non garantisce l'ordine), non la rimette
   lì e lo segnala.
8. **Stesso nome, byte diversi: conflitto.** Nessuno dei due si sovrascrive.
9. **Le call**: le scrive solo il Mac. La copia del testo va in `testi/` (stesso percorso
   relativo dell'archivio) solo quando la call è stabile, e la voce `call` solo dopo che la copia
   è identica all'originale. **L'iPhone i testi li scarica e basta**: mai caricarli, mai
   sovrascriverli; una differenza è un conflitto. Una sottocartella o un file che non è `.txt`
   si segnala.
10. **Il Mac segnala chi ricarica**: se una voce che ha già tolto per lapide ricompare nel
   contenitore, la toglie di nuovo e lo dice.

**Il repo di FlowBridge per iPhone è pubblico**: le fixture qui sono sintetiche, e
`prove/test_contratto_diario.py` fallisce se una contiene un termine del vocabolario dei clienti.
