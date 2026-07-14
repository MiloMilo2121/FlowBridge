# FlowBridge V2 — 20 Killer Feature + UX Super Premium

> Stato: **proposta storica** · Data: 2 luglio 2026 · Complemento di [ROADMAP_V2.md](ROADMAP_V2.md). Per le decisioni UI correnti (Living Voice Field, materiali, motion e iPhone 17 baseline) prevale [DESIGN.md](../DESIGN.md).
>
> Regole invariate: **tutto in locale, zero cloud, poca frizione.** Ogni feature indica l'API iOS che la abilita (verificata nella ricerca di piattaforma), il perché è "killer" rispetto ai competitor, e la fase di roadmap in cui atterra. Le feature marcate ⭐ sono già nella roadmap base e qui vengono elevate a standard "killer"; le altre sono nuove.

---

## Parte 1 — Le 20 killer feature

Organizzate in sei gruppi che seguono il viaggio dell'utente: **Cattura → Intelligenza → Inserimento → Libreria → Fiducia → Delight**.

### Gruppo A — Cattura (il momento magico)

#### 1. ⭐ Flow Press — detta senza aprire l'app
Premi l'Action Button (o il control su Lock Screen/Control Center, o Back Tap): la registrazione parte **senza che l'app si apra**, con la Dynamic Island che si accende all'istante.
- **API:** `AudioRecordingIntent` + Live Activity sincrona (obbligo di piattaforma che diventa il nostro palcoscenico).
- **Perché killer:** nessuna app di dettatura locale ce l'ha; Wispr Flow ce l'ha ma è cloud. È la demo da 10 secondi che vende l'app.
- **Fase:** 1 (bandiera della V2.0).

#### 2. Isola Viva — la Dynamic Island come strumento musicale
L'isola non mostra un'icona statica: mostra un **waveform che respira con la tua voce** (ampiezza reale dal mic), il timer, e in expanded le **ultime parole trascritte che scorrono in tempo reale**. Stop, Annulla e "Inserisci" direttamente dall'isola.
- **API:** ActivityKit con update locali (non throttlati col processo vivo sotto sessione audio), `Text(timerInterval:)` a budget zero, `Button(intent:)` con `LiveActivityIntent` eseguito nel processo app. Ampiezza da `AVAudioEngine` metering.
- **Perché killer:** trasforma un vincolo di piattaforma (Live Activity obbligatoria) nel momento di prodotto più fotografabile. È l'immagine di marketing.
- **Fase:** 1.

#### 3. Cattura al polso e in auto — gratis, senza app Watch
La Live Activity si replica **da sola** nello Smart Stack di Apple Watch, sulla plancia CarPlay e nella menu bar del Mac (iPhone Mirroring): vedi il timer e il transcript ovunque, senza scrivere una riga di codice watchOS.
- **API:** `.supplementalActivityFamilies([.small])` (watchOS 11+, CarPlay iOS 26).
- **Perché killer:** quattro superfici con una implementazione; nessun competitor locale le usa.
- **Fase:** 3.

#### 4. Session Append — riprendi da dove eri
Cammini, detti, ti fermi al semaforo, riprendi: entro una finestra configurabile (default 5 min) la nuova dettatura **si accoda alla precedente** invece di creare una nota nuova. Toggle "nuova/continua" dall'isola expanded.
- **API:** stato di sessione in App Group + logica locale; nessuna API esotica.
- **Perché killer:** risolve il pattern reale del "pensare a raffiche" (JTBD #1 e #5) che oggi produce 6 note frammentate.
- **Fase:** 2.

#### 5. Whisper Mode — detta sussurrando
Profilo di cattura tarato per parlare a **voce bassissima** (ufficio, treno, letto): gain boost, noise floor adattivo, VAD più sensibile, e prompt bias del motore verso parlato soft.
- **API:** `AVAudioEngine` + processing locale del gain/AGC; soglie VAD dedicate; nessun servizio esterno.
- **Perché killer:** il motivo n.1 per cui la gente NON detta in pubblico è l'imbarazzo. Nessun competitor lo affronta come modalità esplicita. Storia di marketing fortissima ("dettatura da biblioteca").
- **Fase:** 2 (spike di fattibilità in Fase 0: misurare WER a basso volume).

### Gruppo B — Intelligenza (tutta on-device)

#### 6. ⭐ Polish Engine a tre livelli
Ogni dettatura esiste in tre versioni istantanee: **Grezzo** (verbatim), **Pulito** (filler via, punteggiatura, capitalizzazione), **Su misura** (tono adattato alla destinazione). Switch con un tap, sempre reversibile — il grezzo non si perde mai.
- **API:** FoundationModels con `@Generable` (una sola passata vincolata produce entrambe le versioni pulite), `prewarm()` durante la registrazione, fallback garantito al grezzo su `guardrailViolation`.
- **Perché killer:** è l'80% della magia "AI" di Wispr a costo marginale zero e senza che un byte lasci il telefono.
- **Fase:** 1.

#### 7. Tono per-app (Context Tone)
La tastiera sa in quale app stai scrivendo (bundle id): il Polisher formatta di conseguenza — **Messages**: minuscole rilassate, niente punto finale; **Mail**: frasi complete, saluti; **Notes/Obsidian**: markdown. Mappatura personalizzabile.
- **API:** bundle id host dalla keyboard extension → App Group → prompt del Polisher. Nessun contenuto dell'app letto, solo l'identità.
- **Perché killer:** feature Pro di Wispr ($15/mese), qui locale e inclusa.
- **Fase:** 2.

#### 8. Il mio Vocabolario — i tuoi nomi, sempre giusti
Lista locale di nomi propri, brand, gergo tecnico. Iniettata nel motore (prompt bias Whisper, `contextualStrings` DictationTranscriber) e usata dal Polisher come dizionario di correzione.
- **Perché killer:** **il gap dichiarato di Apple** — né la dettatura di sistema né la nuova API SpeechTranscriber lo hanno. È la risposta alla domanda "perché non uso quella di Apple?".
- **Fase:** 2.

#### 9. Correzioni che insegnano (Learn-from-Edit)
Quando modifichi il testo appena inserito (dalla cronologia o ridettando), FlowBridge fa il diff locale e ti propone: *"Aggiungo 'Milanello' al vocabolario?"* Un tap e il sistema non sbaglia più.
- **API:** diff testuale locale + `VocabularyStore`; UI con `TipKit` per il suggerimento.
- **Perché killer:** il vocabolario si costruisce da solo usando l'app — nessun competitor chiude questo loop; tutti fanno compilare liste a mano.
- **Fase:** 2.

#### 10. Comandi vocali essenziali — deterministici, non AI
Sei comandi, perfetti: "punto", "virgola", "a capo", "nuovo paragrafo", "cancella ultima frase", "tutto maiuscolo". Sostituzione **deterministica locale** (regex sul transcript finale), non interpretazione LLM — quindi istantanea e prevedibile, in italiano e inglese.
- **Perché killer:** "poche cose fatte bene" applicato ai comandi. La dettatura Apple li ha erratici; i cloud li fanno con latenza.
- **Fase:** 3.

#### 11. Smart Structure — elenchi ed email che si formattano da soli
Se detti "primo… secondo… terzo…" ottieni un elenco puntato; se detti una mail ("ciao Marco, … saluti") ottieni paragrafi, saluto e firma. Il Polisher riconosce la **struttura** del parlato, non solo la grammatica.
- **API:** FoundationModels guided generation con enum di struttura (`.plain / .list / .email / .markdown`) — output vincolato, niente allucinazioni di contenuto.
- **Fase:** 3.

#### 12. Bilingue senza switch (IT ⇄ EN)
Rilevamento automatico della lingua per sessione: detti in italiano, poi in inglese, e ogni dettatura va al motore giusto (`SpeechTranscriber` it_IT / en_US, Whisper come arbitro di language detection). Nessun selettore da toccare.
- **Perché killer:** chi lavora in due lingue (il tuo caso) oggi cambia tastiera/lingua a mano ovunque. Frizione azzerata.
- **Fase:** 2.

### Gruppo C — Inserimento (dove il testo atterra)

#### 13. ⭐ Magic Insert — streaming senza sfarfallio
Il testo appare nel campo attivo **mentre parli**, con diff incrementale (si aggiorna solo la coda instabile, mai delete-all-reinsert), sveglia via Darwin notification (niente polling), e un tasto "↵ Inserisci e invia" per i messaggi.
- **API:** `textDocumentProxy` + `CFNotificationCenter` Darwin; algoritmo di longest-common-prefix per il diff.
- **Perché killer:** la tastiera di Superwhisper è il suo punto più odiato; la nostra deve essere il punto più amato. L'affidabilità qui È la feature.
- **Fase:** 1–2.

#### 14. Snippet Ovunque — il risultato ti raggiunge
Se detti senza tastiera attiva (da Action Button, in giro per il sistema), il risultato appare come **interactive snippet** sopra qualsiasi schermata: rileggi, "Copia", "Condividi", "Manda a Notes" — senza mai aprire FlowBridge.
- **API:** `SnippetIntent` / interactive snippets (iOS 26) con bottoni che concatenano App Intents.
- **Perché killer:** API nuovissima di iOS 26, quasi nessuno la usa ancora: candidatura naturale al featuring editoriale Apple.
- **Fase:** 2.

#### 15. Dettatura come mattoncino — Shortcuts a piena potenza
Azioni Shortcuts ricche: **"Detta testo" restituisce una variabile** utilizzabile in qualsiasi automazione ("detta → aggiungi a lista spesa", "detta → messaggio a Chiara", "detta → entry in Obsidian con data"). Più trigger di automazione iOS 26 (es. alla connessione CarPlay proponi dettatura).
- **API:** App Intents con `ReturnsValue<String>`, parametri (lingua, livello polish), App Shortcuts con frasi Siri. Con iOS 27 la nuova Siri chiamerà gli stessi intents: siamo già pronti.
- **Perché killer:** trasforma FlowBridge da app a **infrastruttura vocale del telefono** — l'utente power costruisce i suoi flussi, e ogni shortcut condiviso è marketing gratuito.
- **Fase:** 2.

#### 16. Azioni dal parlato — da voce a Promemoria e Calendario
Se nella dettatura dici cose tipo "ricordami di chiamare il commercialista giovedì", FlowBridge le riconosce e propone chip actionable sotto il transcript: **[+ Promemoria] [+ Evento]**. Un tap e via, tutto tramite framework locali.
- **API:** FoundationModels guided generation (`actionItems: [ActionItem]` con date parse) + EventKit/Reminders. Le proposte sono opt-in: mai scritture automatiche.
- **Perché killer:** il primo passo "Siri-like" vero — ma privato, e senza pretendere di essere un assistente generale.
- **Fase:** 3.

### Gruppo D — Libreria (la memoria)

#### 17. Cronologia con ricerca semantica locale
Non solo ricerca full-text: chiedi *"quella cosa che avevo detto sul contratto"* e la trovi, grazie a embedding on-device. Filtri per app di destinazione, lingua, data; pin e cartelle.
- **API:** `NLEmbedding`/`NLContextualEmbedding` (Natural Language framework, on-device) + indice locale; zero rete.
- **Perché killer:** i cloud lo fanno sul server; noi sul telefono. "Il tuo archivio vocale che non ha mai lasciato la tua tasca."
- **Fase:** 3.

#### 18. Testo⇄Audio sincronizzati (tap-to-listen)
Nella cronologia ogni parola è agganciata al suo istante audio: **tocchi una parola e riascolti quel punto**. Utile per verificare nomi/cifre nelle dettature professionali (avvocati, medici).
- **API:** `audioTimeRange` per-run di SpeechTranscriber (AttributedString con CMTimeRange) / word timestamps WhisperKit; audio conservato con retention configurabile (default 24h, poi auto-delete — coerente con la privacy).
- **Perché killer:** feature da tool professionale desktop, portata su iPhone, locale. Nessun competitor mobile la offre.
- **Fase:** 3.

#### 19. Ritrascrivi con Precision
Qualsiasi dettatura recente si può riprocessare col motore Whisper turbo ("Precision") o con vocabolario aggiornato: l'audio è ancora lì (finché la retention lo consente), il risultato migliora, il confronto è side-by-side.
- **Perché killer:** chiude il loop qualità: prima velocità (SpeechTranscriber), poi accuratezza (Whisper) — solo quando serve, senza rifare la dettatura.
- **Fase:** 2.

### Gruppo E — Fiducia (privacy dimostrabile) e Gruppo F — Delight

#### 20. Privacy Cockpit + "Tempo restituito"
Una schermata due-in-uno che nessun competitor può copiare onestamente:
- **Privacy Cockpit:** contatore live delle connessioni di rete bloccate da `NetworkGuard` (sempre zero richieste audio, e lo vedi), retention audio con countdown, bottone "Prova in modalità aereo" che ti guida a dettare con la rete spenta. La privacy come **dashboard verificabile**, non come paragrafo legale.
- **Tempo restituito:** statistiche 100% locali — parole dettate, WPM medio vs digitazione, **minuti di vita risparmiati** questa settimana, streak. Condivisibile come card immagine (generata on-device) per il passaparola.
- **API:** dati già in nostro possesso + rendering locale; niente analytics remoti, mai.
- **Perché killer:** l'angolo 2 (fiducia) e la crescita organica (share card) nella stessa schermata. La card "Questa settimana ho recuperato 47 minuti parlando invece di digitare — offline" è il nostro growth loop.
- **Fase:** 3.

### Vista d'insieme

| # | Feature | Gruppo | Fase | Sforzo | Rischio tecnico |
|---|---|---|---|---|---|
| 1 | Flow Press | Cattura | 1 | M | Medio (spike previsto) |
| 2 | Isola Viva | Cattura | 1 | M | Basso |
| 3 | Watch/CarPlay relay | Cattura | 3 | S | Basso |
| 4 | Session Append | Cattura | 2 | S | Basso |
| 5 | Whisper Mode | Cattura | 2 | M | Medio (WER a basso volume) |
| 6 | Polish Engine 3 livelli | Intelligenza | 1 | M | Basso |
| 7 | Tono per-app | Intelligenza | 2 | S | Basso |
| 8 | Il mio Vocabolario | Intelligenza | 2 | M | Basso |
| 9 | Learn-from-Edit | Intelligenza | 2 | S | Basso |
| 10 | Comandi essenziali | Intelligenza | 3 | S | Basso |
| 11 | Smart Structure | Intelligenza | 3 | M | Basso |
| 12 | Bilingue auto | Intelligenza | 2 | M | Medio |
| 13 | Magic Insert | Inserimento | 1–2 | M | Medio (edge case host app) |
| 14 | Snippet Ovunque | Inserimento | 2 | M | Medio (API nuova) |
| 15 | Shortcuts a piena potenza | Inserimento | 2 | S | Basso |
| 16 | Azioni dal parlato | Inserimento | 3 | M | Basso |
| 17 | Ricerca semantica | Libreria | 3 | M | Basso |
| 18 | Tap-to-listen | Libreria | 3 | M | Basso |
| 19 | Ritrascrivi Precision | Libreria | 2 | S | Basso |
| 20 | Privacy Cockpit + Tempo restituito | Fiducia/Delight | 3 | M | Basso |

*(S = giorni, M = 1–2 settimane. Le fasi si riferiscono alla roadmap in ROADMAP_V2.md; questa lista ne è il riempimento feature-level.)*

---

## Parte 2 — UX Super Premium: "giocare con iOS"

Obiettivo: FlowBridge deve **sembrare un pezzo di iOS**, non un'app installata sopra. Il premium non è decorazione: è fisica, aptica, coerenza e velocità percepita. Riferimento qualitativo: le app che Apple mette in vetrina (Flighty, Tiimo, Detail).

### 2.1 Linguaggio visivo — Liquid Glass nativo

- **Materiali di sistema, non ricreati**: superfici in Liquid Glass (iOS 26) con `glassEffect` e gerarchia a due soli livelli — lo sfondo "stanza" e le carte flottanti. Niente chrome custom: quando iOS cambia, FlowBridge cambia con lui.
- **Un colore, usato con avarizia**: accent "Flow Violet" (viola-blu elettrico) riservato a **un solo significato**: lo stato di ascolto. Registrazione = rosso di sistema. Successo = verde di sistema. Tutto il resto è monocromo su materiali. Il colore diventa informazione, non decorazione.
- **Tipografia**: SF Pro con Display per il transcript (il testo È il prodotto: corpo grande, 20–22pt di default), SF Mono per i numeri del timer (allineamento stabile), Dynamic Type ovunque senza eccezioni.
- **Icona**: forma d'onda che si piega a ponte (il "bridge"), variante dark e tinted (iOS 18+ icon system), niente gradienti datati.
- **La schermata principale è una sola**: la "stanza". Al centro l'**Orb** — un blob fluido renderizzato con Metal shader che respira da fermo, si increspa con la tua voce quando ascolti, si condensa in testo quando finisci. Tutto il resto (cronologia, impostazioni) sta sotto, in una sheet trascinabile. Un'app di dettatura non ha bisogno di tab bar.

### 2.2 Vocabolario aptico (CoreHaptics, file AHAP)

L'aptica è il canale principale di feedback — l'utente spesso NON guarda lo schermo (Action Button in tasca, camminando). Definiamo un vocabolario fisso, mai riutilizzato per altri significati:

| Evento | Pattern | Design |
|---|---|---|
| Inizio ascolto | "Heartbeat up" | due tap crescenti (0.4 → 0.8 intensità, 80ms gap) — *ti sto ascoltando* |
| Fine ascolto | "Heartbeat down" | speculare decrescente — *ho finito di ascoltare* |
| Testo pronto | "Crystal" | transient secco + micro-continuous 60ms — *fatto, è in clipboard* |
| Inserito nel campo | doppio tick leggero | conferma senza disturbo |
| Errore/recupero | "Rumble" morbido 200ms | mai punitivo: c'è sempre l'AudioSafetyBuffer |
| Waveform live (opzionale, toggle) | micro-transients sincronizzati ai picchi voce | l'Orb "si sente" sotto il dito durante il fine-tuning del gain in Whisper Mode |

- **API:** `CoreHaptics` con pattern AHAP file-based (tuning senza ricompilare), fallback `UIFeedbackGenerator` su device senza engine.
- Regola: **ogni evento udibile ha un gemello aptico e viceversa** — l'app è pienamente usabile da sordi e da chi tiene il telefono in tasca.

### 2.3 Suono (opzionale, off di default)

Due earcons proprietari totalmente discreti — "pluck" di inizio (80ms) e "resolve" di fine (120ms), stessa famiglia timbrica, registrati ad hoc — rispettano l'interruttore silenzioso e il routing (mai negli AirPods altrui via SharePlay). Il suono è un lusso raro, non un tappeto.

### 2.4 Coreografia della Dynamic Island

L'isola è il nostro palcoscenico principale; la trattiamo come una sequenza di **stati morfologici** con transizioni fluide, non come un widget:

```
idle ──(Flow Press)──► LISTENING     compact: waveform vivo + timer
                            │        expanded: ultime ~8 parole in scroll + [Stop] [✕]
                       (stop)
                            ▼
                       POLISHING     compact: waveform si condensa in tre puntini che "pensano"
                            │        (durata reale: <1–2s, prewarm già fatto)
                            ▼
                       READY         compact: ✓ + prime parole; expanded: [Inserisci] [Copia] [Apri]
                            │        auto-dismiss dopo 6s → resta in cronologia
                            ▼
                       (dismiss)
```

- Il passaggio LISTENING → POLISHING → READY usa **una sola forma che si trasforma** (il waveform diventa puntini diventa spunta) — mai tre icone che si sostituiscono. Percezione: un organismo, non una UI.
- Timer con `Text(timerInterval:)` (zero budget, sempre fluido); anteprima parole via update locali.
- Su device bloccato i bottoni richiedono sblocco (regola iOS): il layout lock-screen privilegia quindi la **lettura** (transcript grande) e lascia le azioni al post-sblocco.
- Long-press dall'isola in qualunque stato = expanded con tutto il controllo. L'app non serve mai.

### 2.5 Animazioni: fisica, non durata

- **Solo spring** (`.spring(response:dampingFraction:)`), mai ease-in-out a durata fissa: le molle si interrompono con grazia quando l'utente incalza.
- **`matchedGeometryEffect`** tra l'Orb, la pillola dell'isola e la card in cronologia: il transcript "viaggia" fisicamente da dove nasce a dove vive. È il signature move dell'app.
- **`contentTransition(.numericText())`** su timer e contatori (statistiche che "rullano").
- **SF Symbols animati**: `variableColor` sul simbolo waveform durante l'ascolto, `bounce` sulla spunta di successo, `replace.downUp` nei cambi di stato dei bottoni.
- **Il testo arriva come dettato**: le parole nuove appaiono con fade+rise di 12pt, parola per parola, in sincrono con lo stream del motore. Vedere il proprio parlato materializzarsi è il momento di soddisfazione centrale — va coreografato, non "printato".
- **Budget di performance come vincolo UX**: 120Hz ProMotion sempre; cold start della stanza < 400ms; zero hitch nello scroll cronologia (prefetch + cell riuso). Un'app "premium" che scatta non esiste.
- **Reduce Motion**: ogni animazione ha la variante cross-fade. Non è un ripiego: è la stessa cura, in un altro dialetto.

### 2.6 Onboarding cinematografico (3 scene, 90 secondi)

1. **Scena 1 — "Parla."** Nessuna spiegazione: la prima schermata È l'Orb con "Tieni premuto e di' qualcosa". L'utente detta *prima* di sapere come funziona l'app. Il permesso microfono arriva contestuale, nel momento del gesto (just-in-time, non wall di permessi).
2. **Scena 2 — "Il tuo bottone."** Setup guidato dell'Action Button con video inline di 5 secondi e deep-link diretto alle Impostazioni. Se il device non ha Action Button: Back Tap o control Lock Screen, stessa cura.
3. **Scena 3 — "La tua tastiera (opzionale)."** Full Access spiegato con onestà brutale e una riga sola: *"iOS mostra un avviso spaventoso. Ecco cosa facciamo davvero: leggiamo il tuo transcript dal contenitore condiviso. Ecco cosa non possiamo fare: mandarlo a chiunque — l'app non parla con internet, e puoi verificarlo nel Privacy Cockpit."* Skippabile: l'app è utile anche solo con clipboard e snippet.
- Progressive disclosure dopo l'onboarding via **TipKit** (i tip escono quando il contesto li rende ovvi: il tip sul vocabolario appare alla prima correzione, non al giorno zero).

### 2.7 Stati vuoti e microcopy

- Tono di voce: **asciutto, caldo, mai infantile**. In italiano vero, non tradotto ("Nessuna dettatura ancora. Il tuo Action Button si annoia.").
- Ogni stato d'errore dice tre cose: cosa è successo, cosa abbiamo già salvato (sempre tutto, grazie all'AudioSafetyBuffer), e l'unico tasto per rimediare.
- Mai un alert di sistema dove basta un banner inline.

### 2.8 Accessibilità come tratto premium (e come mercato)

Gli utenti RSI/ADHD/low-vision sono un segmento core (angolo 3), non un requisito di conformità:
- VoiceOver completo con label semantiche sul flusso di registrazione (l'ironia di un'app vocale non accessibile a chi usa la voce per necessità sarebbe letale).
- Tutte le azioni raggiungibili senza toccare lo schermo: Action Button + comandi vocali + Siri phrase.
- Dynamic Type fino ad AX5 senza layout rotti; contrasto AAA sul transcript.
- **StandBy** (iPhone in orizzontale in carica): vista notturna con bottone di cattura gigante e ultima nota — il comodino diventa un registratore di idee da sogno, letteralmente.

### 2.9 Widget e superfici ambientali

- **Home Screen**: widget small (bottone cattura + streak) e medium (ultime 2 dettature, tap = copia).
- **Lock Screen**: control al posto della torcia (iOS 18+); widget inline con conteggio parole del giorno.
- **StandBy**: v. sopra.
- Tutte le superfici usano gli **stessi App Intents** — una sola logica, N punti d'ingresso: coerenza garantita by design.

### 2.10 Definition of "premium" (checklist di rilascio per ogni build)

- [ ] Ogni interazione ha feedback entro 100ms (aptico, visivo o entrambi).
- [ ] Nessuna animazione a durata fissa; tutte interrompibili.
- [ ] Cold start < 400ms; press-to-listening < 1,5s; stop-to-ready < 2s.
- [ ] Zero testo troncato ad AX5; VoiceOver audit passato.
- [ ] L'app funziona per intero in modalità aereo (test automatico in CI con NetworkGuard in assert-mode).
- [ ] Reduce Motion, Reduce Transparency, Increase Contrast: varianti verificate.
- [ ] Ogni nuova feature raggiungibile in ≤ 2 gesti dal trigger fisico, o non si spedisce.

---

## Impatto sulla roadmap

Le fasi di [ROADMAP_V2.md](ROADMAP_V2.md) restano valide; questo documento le riempie a livello feature. Aggiornamenti proposti:

- **Fase 0** guadagna lo spike Whisper Mode (misura WER a basso volume) accanto allo spike `AudioRecordingIntent`.
- **Fase 1** = feature 1, 2, 6, 13 (prima metà) + fondamenta UX §2.1–2.5 (il vocabolario aptico e la coreografia dell'isola nascono col prodotto, non si aggiungono dopo).
- **Fase 2** = feature 4, 5, 7, 8, 9, 12, 13 (completa), 14, 15, 19 + onboarding §2.6.
- **Fase 3** = feature 3, 10, 11, 16, 17, 18, 20 + superfici ambientali §2.9 + checklist §2.10 in CI.

Nessuna feature richiede rete. Nessuna feature richiede riscrittura del codice V1.
