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

**Il repo di FlowBridge per iPhone è pubblico**: le fixture qui sono sintetiche, e
`prove/test_contratto_diario.py` fallisce se una contiene un termine del vocabolario dei clienti.
