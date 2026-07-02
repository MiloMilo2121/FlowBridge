# FlowBridge V2 — Roadmap e Piano Strategico

> Stato: **proposta** · Data: 2 luglio 2026 · Base: FlowBridge V1 completata (dettatura offline con WhisperKit, keyboard extension, App Intent per Action Button/Back Tap)
>
> Principio guida della V2: **poche cose, fatte benissimo, tutte in locale.** Nessun cloud, mai. Il codice V1 si conserva integralmente: la V2 è additiva, non una riscrittura.
>
> Documento correlato: [KILLER_FEATURES_V2.md](KILLER_FEATURES_V2.md) — le 20 killer feature e la specifica UX super premium che riempiono a livello feature le fasi di questa roadmap.

---

## Indice

1. [Visione ed executive summary](#1-visione-ed-executive-summary)
2. [Cosa dice il mercato (ricerca competitor, luglio 2026)](#2-cosa-dice-il-mercato)
3. [Il nostro angolo di mercato](#3-il-nostro-angolo-di-mercato)
4. [Jobs-to-be-done e descrizione App Store](#4-jobs-to-be-done-e-descrizione-app-store)
5. [Fondamenta tecniche verificate (cosa si può e non si può fare)](#5-fondamenta-tecniche-verificate)
6. [Architettura V2](#6-architettura-v2)
7. [Roadmap per fasi](#7-roadmap-per-fasi)
8. [Cosa NON faremo (non-goals)](#8-cosa-non-faremo-non-goals)
9. [Monetizzazione](#9-monetizzazione)
10. [Rischi e mitigazioni](#10-rischi-e-mitigazioni)
11. [Metriche di successo](#11-metriche-di-successo)
12. [Fonti principali](#12-fonti-principali)

---

## 1. Visione ed executive summary

**FlowBridge V2 è il percorso più corto tra pensiero e testo mai realizzato su iPhone — interamente sul dispositivo.**

Un solo gesto fisico (Action Button), la registrazione parte *senza nemmeno aprire l'app*, la Dynamic Island mostra il waveform e il timer in tempo reale, e quando ti fermi il testo — già ripulito da "ehm", riempitivi e punteggiatura sbagliata da un LLM on-device — è pronto per essere inserito ovunque. Niente cloud, niente account, niente abbonamento. Non è una privacy policy: è fisica.

Le tre scommesse della V2:

1. **Integrazione iOS più profonda di chiunque altro nel campo "locale"**: Dynamic Island interattiva, Action Button con avvio in background (`AudioRecordingIntent`), Control Center, Lock Screen, Siri/App Shortcuts. Oggi solo Wispr Flow (cloud-only) ha questa profondità; nessuna app locale ce l'ha. È un varco aperto.
2. **Motore ibrido 100% locale**: Apple `SpeechTranscriber` (iOS 26) come default — nei benchmark indipendenti 2026 è il migliore in assoluto sull'italiano (WER 4,0%) ed è ~2× più veloce di Whisper large-v3-turbo — con WhisperKit come motore "Precision" per il vocabolario personalizzato, il buco che Apple ha lasciato aperto. Post-processing con Apple Foundation Models (LLM 3B on-device, italiano supportato, costo zero).
3. **Affidabilità come feature di punta**: il reclamo n.1 contro l'unico vero concorrente locale (Superwhisper) è la tastiera iOS che perde registrazioni. Una pipeline locale non ha round-trip server che possano fallire: "non perdi mai una dettatura" diventa garanzia architetturale e messaggio di marketing.

L'hardware di riferimento (iPhone Air: A19 Pro, **12 GB di RAM**, Dynamic Island, Action Button) è nel tier più alto supportato da Apple — c'è margine abbondante per Whisper + LLM 3B contemporaneamente in memoria.

---

## 2. Cosa dice il mercato

*Ricerca condotta a luglio 2026 su ~70 fonti web. Dettaglio fonti in §12.*

### 2.1 Il quadro in breve

La dettatura vocale è passata da utility di nicchia a categoria calda nel 2025–2026. Wispr Flow ha raccolto ~$81M fino a novembre 2025 e ha chiuso (riportato) un Series B da ~$260M a valutazione ~$2B a maggio 2026 — legittimando la categoria e attirando una ondata di concorrenti YC (Willow, Aqua), indie (Superwhisper, VoiceInk, Spokenly, Whisper Notes) e persino hardware maker (Nothing "Essential Voice"). Le due linee di faglia del mercato: **cloud vs locale** e **abbonamento vs acquisto una tantum**.

### 2.2 Profili competitor sintetici

| Competitor | Locale? | Tastiera iOS | Action Button | Dynamic Island | Prezzo | Debolezza chiave |
|---|---|---|---|---|---|---|
| **Wispr Flow** (leader, ~$2B) | ❌ cloud-only, nessun piano offline | ✅ | ✅ | ✅ (interattiva, giu 2026) | $15/mese | Privacy (scandalo screenshot), latenza 1–2s, inutile offline, Trustpilot 2,7/5 |
| **Superwhisper** | ✅ (Whisper + Parakeet) | ✅ ma **notoriamente buggata** | non in evidenza | ❌ | $8,49/mese o $249,99 lifetime | Registrazioni perse su iOS, setup complesso |
| **Willow Voice** (YC) | ❌ cloud | ✅ (+voice editing) | ❌ | ❌ | $15/mese | Clone di Wispr, stessa storia privacy |
| **Aqua Voice** (YC) | ❌ cloud | ✅ (apr 2026) | ❌ | ❌ | $8/mese, iOS $119/anno separato | Pricing confuso, cloud |
| **VoiceInk** | ✅ open source | debole, trascurata | ❌ | ❌ | $25–49 una tantum (Mac) | Esecuzione iOS scarsa |
| **Aiko** | ✅ gratis | ❌ (non è tastiera) | ❌ | ❌ | gratis | Solo trascrizione file, non dettatura |
| **Spokenly / Whisper Notes** | ✅ | parziale | ❌ | ❌ | gratis / $6,99 | Poca profondità di integrazione |
| **Dettatura Apple** (iOS 26/27) | ✅ | nativa | nativa | n/a | gratis | **Niente vocabolario custom**, punteggiatura erratica, timeout, filler verbatim; la dettatura migliorata di iOS 27 è **esclusiva dei device con 12GB+ RAM** |

### 2.3 I reclami più frequenti degli utenti (sintesi App Store / Reddit / Trustpilot)

1. **Fatica da abbonamento** — "la dettatura è una utility, non un servizio da $180/anno". Il segmento one-time/lifetime cresce (6,4% → 10,3% del mercato 2023–2025).
2. **Affidabilità > accuratezza** — registrazioni perse è il trigger di rabbia n.1 (Superwhisper iOS, Wispr long-form).
3. **Latenza** — i round-trip cloud da 1–2s+ rompono il flusso; inutilizzabili offline.
4. **Frizione tastiera** — il balletto di cambio tastiera, permesso Full Access che spaventa, conflitti con l'autocorrezione.
5. **Privacy** — dopo lo scandalo screenshot di Wispr, "la mia voce lascia il telefono?" è una domanda mainstream. I recensori ormai distinguono "Privacy Mode" (ritenzione zero ma processing remoto) da "locale".

### 2.4 La finestra strategica su Siri

- La nuova "Siri AI" (annunciata WWDC 2026, powered by Gemini via Private Cloud Compute) è un **assistente cloud, non un motore di dettatura**. Arriva con iOS 27 a fine 2026.
- La dettatura di sistema è peggiorata secondo molti utenti (timeout aggressivi, parole perse, nessun toggle per sistemarla), e la versione migliorata in beta iOS 27 (modello AFM Core Advanced) è **riservata a iPhone 17 Pro / iPhone Air / device con 12GB+ RAM** — l'intera base installata precedente resta scoperta.
- Gap persistenti di Apple: niente vocabolario custom (nemmeno nella nuova API SpeechAnalyzer), niente rimozione filler, niente formattazione per-app, niente cronologia.

**Conclusione: c'è una finestra di 12–24 mesi per possedere "dettatura di qualità, a bassa frizione, offline, su ogni iPhone".**

---

## 3. Il nostro angolo di mercato

La ricerca ha identificato tre angoli percorribili. La raccomandazione è usarli **tutti e tre, a livelli diversi**:

### Angolo 1 — "La dettatura che Apple avrebbe dovuto fare" *(lancio, mass market)*
Target: ogni utente iPhone frustrato dai timeout di Siri, dalle parole perse, dai filler trascritti. Cavalca il ciclo di notizie Siri/Gemini. Distribuzione: ASO su query "dettatura non funziona / voice typing", demo TikTok fianco-a-fianco Siri vs FlowBridge, Action Button + Dynamic Island come visual eroe.

### Angolo 2 — "Privato per architettura, non per policy" *(pricing, professionisti)*
Target: avvocati, medici, terapeuti, giornalisti — chi ha obblighi reali di riservatezza (l'82% degli studi legali usa già software di dettatura). FlowBridge non ha nulla da violare: niente server, niente account, niente audio da citare in giudizio presso terzi. Su questo segmento si costruisce il paywall (hard paywall converte ~5× meglio del freemium — dati RevenueCat 2026) e il prezzo lifetime.

### Angolo 3 — "Cattura del pensiero a zero frizione" *(design di prodotto, editorial Apple)*
Target: chi cammina, chi ha ADHD, chi ha RSI/tunnel carpale. È l'angolo che l'editorial di Apple premia (accessibilità + benessere + vetrina delle API native: Action Button, Dynamic Island, App Intents, Foundation Models). Il prodotto si progetta attorno a questo angolo; il marketing di lancio usa l'angolo 1; il pricing l'angolo 2.

**Posizionamento sintetico (bozza):**

> *FlowBridge è la dettatura che ti sta dietro. Mentre Siri ti taglia a metà frase, FlowBridge ascolta finché parli, toglie gli "ehm", mette la punteggiatura e ti consegna testo pulito ovunque ti serva — una pressione dell'Action Button, un waveform vivo nella Dynamic Island, e mai un'icona di caricamento cloud. Gira interamente sul tuo iPhone: funziona in metro, in aereo, in modalità aereo. La tua voce non lascia mai il telefono, e il tuo portafoglio non sanguina un abbonamento.*

La regola di messaging emersa dalla ricerca: **guidare col beneficio percepito (velocità, zero sforzo), usare locale/no-abbonamento come moltiplicatore di fiducia** — non come titolo. "Privacy-first" da solo è una feature; "5× più veloce, e non lascia mai il tuo telefono" è una posizione.

---

## 4. Jobs-to-be-done e descrizione App Store

*(Nota: nella richiesta vocale originale compare "descrizione della JCB" — interpretato come JTBD, jobs-to-be-done, e come richiesta della descrizione prodotto/App Store. Coperti entrambi qui; se intendevi altro, questa sezione si aggiorna.)*

### 4.1 I cinque job principali

| # | Job | Trigger | Cosa deve essere vero |
|---|---|---|---|
| 1 | **Catturare un'idea camminando** | idea che evapora, mani occupate | dal click al parlato < 1 secondo, senza guardare lo schermo |
| 2 | **Rispondere a messaggi velocemente** | tastiera mobile lenta, autocorrezione ostile | inserimento diretto nel campo di testo attivo, tono informale |
| 3 | **Bozze lunghe (scrittori, avvocati, medici)** | mantenere il momentum, evitare RSI | nessun timeout, vocabolario di dominio, testo già formattato |
| 4 | **Note vocali in mobilità/guida** | sicurezza, hands-free | trigger senza schermo (Action Button, Siri), risultato affidabile |
| 5 | **Pensiero ADHD alla velocità del pensiero** | attenzione frammentata | zero passaggi tra il pensiero e il testo salvato |

Il prodotto che vince è quello con **il percorso idea→testo-pulito più corto**. Ogni decisione di design della V2 si giudica contro questa frase.

### 4.2 Bozza descrizione App Store (IT)

> **FlowBridge — Detta. Ovunque. Offline.**
>
> Premi l'Action Button e parla: FlowBridge trascrive la tua voce direttamente sul tuo iPhone, toglie i riempitivi, sistema la punteggiatura e inserisce il testo pulito dove stai scrivendo. Nessun cloud. Nessun account. Nessun abbonamento.
>
> • **Un gesto, zero attese** — Action Button, Control Center, Back Tap o "Ehi Siri": la registrazione parte all'istante, con waveform e timer nella Dynamic Island.
> • **100% sul dispositivo** — la trascrizione e la pulizia del testo con AI avvengono interamente sul tuo iPhone. Funziona in modalità aereo. La tua voce non lascia mai il telefono: non è una promessa, è architettura.
> • **Testo già pulito** — l'intelligenza on-device di Apple rimuove gli "ehm", corregge la punteggiatura e adatta il tono all'app in cui scrivi.
> • **Il tuo vocabolario** — nomi propri, termini tecnici, gergo del tuo lavoro: FlowBridge li impara (cosa che la dettatura di sistema non fa).
> • **Non perdi mai una dettatura** — l'audio è al sicuro sul dispositivo finché il testo non è consegnato. Sempre.
> • **Paghi una volta** — niente canone mensile per usare la tua stessa voce.

*(Versione EN da preparare in fase di lancio; stessa struttura.)*

---

## 5. Fondamenta tecniche verificate

*Ogni voce è stata verificata con ricerca dedicata (fonti in §12). Verdetti: ✅ possibile · ⚠️ possibile con caveat · ❌ non possibile.*

### 5.1 Trigger e avvio registrazione

| Idea | Verdetto | Dettaglio |
|---|---|---|
| Avviare la registrazione **in background** (senza aprire l'app) da Action Button / Control Center / Live Activity | ⚠️ **Possibile, via `AudioRecordingIntent` (iOS 18+)** | È l'API sanzionata da Apple esattamente per questo. Vincolo documentato: **bisogna avviare una Live Activity nel momento in cui parte la registrazione e tenerla attiva per tutta la durata, altrimenti il sistema ferma l'audio**. Permesso microfono già concesso in precedenza (nessun prompt da background). Segnalati errori residui in alcuni contesti trigger → serve fallback con `openAppWhenRun = true`. |
| Continuare a registrare mentre l'utente cambia app | ✅ | `UIBackgroundModes: audio` (già presente in V1) + sessione `.record`/`.playAndRecord` attiva. Nessun limite di tempo di sistema; termina solo per interruzioni (chiamate, Siri) o kill. |
| Avviare una sessione audio *ex novo* dal background senza AudioRecordingIntent | ❌ | Regola DTS confermata: il background audio permette solo di *continuare* una sessione creata in foreground. |
| Camera Control come trigger | ❌ | Riservato ad app con esperienza fotocamera (`LockedCameraCapture` richiede viewfinder immediato). Non per app di dettatura. |
| Stem press AirPods come trigger | ❌ (per ora) | In iOS 26 è mappato solo a Camera. Ma gli AirPods sono ottimi come **microfono** (registrazione Bluetooth ad alta qualità, `bluetoothHighQualityRecording`, iOS 26). |
| Siri phrase ("Ehi Siri, FlowBridge") | ✅ | App Shortcuts con frasi. Con iOS 27, la nuova Siri AI chiamerà gli stessi App Intents (SiriKit deprecato) — investimento a prova di futuro. |

### 5.2 Dynamic Island / Live Activities (ActivityKit)

| Aspetto | Fatto verificato |
|---|---|
| Presentazioni | compact (leading+trailing), minimal, expanded (long-press), lock screen. Expanded ≤ 160pt di altezza. |
| Timer che si aggiorna da solo | `Text(timerInterval:)` si auto-aggiorna **senza consumare budget** — perfetto per il timer di registrazione. |
| Aggiornamenti locali | `Activity.update(_:)` dal processo app (vivo grazie alla sessione audio) è di fatto non throttlato → possiamo aggiornare l'anteprima del transcript in near-real-time. Payload ≤ 4KB. |
| Bottoni interattivi | ✅ in expanded e lock screen (iOS 17+), via `Button(intent:)`. Gli intent audio (`AudioRecordingIntent`, `LiveActivityIntent`) girano **nel processo dell'app** — quindi Stop/Pausa dal bottone dell'isola funzionano in modo affidabile. |
| Caveat device bloccato | Con device bloccato i bottoni richiedono autenticazione. |
| Durata | max 8h attiva (non è un problema: le dettature durano minuti). |
| Bonus gratis | iOS 26 inoltra automaticamente le Live Activities a **CarPlay** (bottoni non funzionanti lì) e, con `.supplementalActivityFamilies([.small])`, allo **Smart Stack di Apple Watch** (watchOS 11+) e alla **menu bar del Mac** via iPhone Mirroring. Una sola implementazione, quattro superfici. |

### 5.3 Motori di trascrizione (tutti on-device)

| Motore | Italiano | Velocità | Vocabolario custom | Note |
|---|---|---|---|---|
| **Apple `SpeechTranscriber`** (iOS 26, framework Speech nuovo) | ✅ it_IT dal lancio — **miglior WER italiano nei benchmark indipendenti 2026 (4,0%)** | ~2× più veloce di Whisper large-v3-turbo | ❌ (gap confermato) | Modello in storage di sistema: **zero peso nell'app, zero memoria a nostro carico**, aggiornato dall'OS. Streaming con risultati volatili + finalizzati. Richiede A14+. |
| **Apple `DictationTranscriber`** (stesso framework) | ✅ | buona | ✅ `contextualStrings` + custom LM | Il ripiego per il biasing di vocabolario nella famiglia Apple. |
| **WhisperKit large-v3-turbo** (argmax-oss-swift v1.0, MIT) | ✅ | streaming con latenza ipotesi ~0,45s | ✅ via prompt biasing | Compresso a **626MB** con WER entro 1% dall'originale. WER ~2% su testo confermato in streaming. Il nostro attuale stack (V1 usa Whisper Small). |
| **Parakeet v3** (Argmax Pro SDK, commerciale) | ✅ (25 lingue EU) | >10× Whisper large | ✅ (Pro, fino a ~3.000 keyword) | Opzione futura se si vuole il top; richiede licenza Pro. Esistono port CoreML community (FluidInference). |

**Decisione architetturale V2: motore ibrido.** `SpeechTranscriber` come default (italiano migliore, più veloce, zero footprint), WhisperKit come motore "Precision" quando l'utente ha un vocabolario personalizzato o una lingua/scenario dove Whisper vince. L'astrazione `TranscriptionEngine` rende i motori intercambiabili e il confronto misurabile.

### 5.4 Post-processing con Apple Foundation Models (LLM on-device)

- Framework `FoundationModels` (iOS 26): LLM ~3B on-device, **niente rete, niente API key, costo zero**. **Italiano supportato dal lancio.**
- Pensato esattamente per il nostro caso: "summarization, text refinement" è il suo sweet spot dichiarato.
- Finestra di contesto **4.096 token** (istruzioni+input+output combinati) → una passata singola copre ~1.500–1.800 parole di dettatura; oltre, chunking. iOS 27 raddoppia a 8.192.
- **Guided generation** (`@Generable`): output strutturato garantito — es. `{cleanedText, title, actionItems}` in una sola passata vincolata, senza parsing JSON.
- `session.prewarm()` durante la registrazione elimina il cold start (1–2s): quando l'utente si ferma, il modello è già caldo.
- Errori da gestire con **fallback al transcript grezzo**: `guardrailViolation` (falsi positivi documentati su contenuti sensibili — critico per dettature mediche/legali), `exceededContextWindowSize`, `rateLimited` (solo background), `unavailable` (Apple Intelligence spenta).
- Su iPhone Air gira anche il tier "Advanced" (20B sparse, iOS 27) — ma progettiamo per il 3B, così funziona su tutta la base Apple Intelligence (iPhone 15 Pro+).

### 5.5 Keyboard extension: limiti permanenti (architettura V1 confermata giusta)

- ❌ Il microfono è **vietato per sempre** alle keyboard extension (enforcement a runtime, non solo policy).
- Tetto memoria empirico **~60–70MB** → nessun modello nella tastiera, mai.
- ❌ Nessuna API supportata per aprire l'app contenitore dalla tastiera (il vecchio hack `openURL` è rotto da iOS 18) — ecco perché i flussi "bounce" di Wispr/Superwhisper sono fragili. Il nostro modello (trigger fisico → app/intent registra, tastiera inserisce) **aggira il problema strutturalmente**.
- ✅ Upgrade possibile: **Darwin notifications** (`CFNotificationCenter`) per svegliare la tastiera al cambio di snapshot invece del polling a 250ms → latenza di inserimento più bassa e meno CPU.
- Contesto documento limitato (`documentContextBeforeInput`, ~300 caratteri) — sufficiente per capitalizzazione/spaziatura contestuale.

### 5.6 Hardware di riferimento (iPhone Air)

- A19 Pro (GPU 5-core con Neural Accelerators, ANE 16-core), **12GB RAM** — Whisper turbo compresso (626MB) + LLM 3B coesistono comodamente.
- **Niente vapor chamber**: sotto stress sostenuto throttla (CPU 76% / GPU 61% di stabilità). Le dettature sono burst brevi → non impattate; da evitare pipeline di inferenza continua di lunga durata (trascrizione file lunghi: mostrare progresso e accettare il throttling).
- Action Button ✅, Camera Control ✅ (ma inutilizzabile per noi, v. sopra), Dynamic Island ✅.

---

## 6. Architettura V2

### 6.1 Diagramma dei flussi

```
                     ┌────────────────────────────────────────────────┐
   Action Button ────┤                                                │
   Control Center ───┤  AudioRecordingIntent (background, no UI)      │
   Back Tap ─────────┤  → FlowBridgeRecorder (sessione .record)       │
   "Ehi Siri…" ──────┤  → Live Activity AVVIATA SUBITO (obbligo API)  │
   Widget/app ───────┤                                                │
                     └───────────────┬────────────────────────────────┘
                                     │ audio buffer (crash-safe, su disco App Group)
                                     ▼
                     ┌────────────────────────────────────────────────┐
                     │  TranscriptionEngine (protocollo)              │
                     │   ├─ AppleSpeechEngine (SpeechTranscriber)     │  ← default
                     │   └─ WhisperEngine (WhisperKit turbo 626MB)    │  ← "Precision" / vocabolario
                     └───────────────┬────────────────────────────────┘
                                     │ stream volatile+final → LiveTranscriptStore
                                     │                       → Activity.update() (isola)
                                     ▼
                     ┌────────────────────────────────────────────────┐
                     │  TranscriptPolisher (FoundationModels, prewarm)│
                     │   filler → via · punteggiatura · tono per-app  │
                     │   fallback: transcript grezzo, sempre          │
                     └───────────────┬────────────────────────────────┘
                                     │ Darwin notification + App Group
                     ┌───────────────┴────────────────┬───────────────┐
                     ▼                                ▼               ▼
              Keyboard extension              Clipboard        Cronologia locale
              (insertText streaming)          (come V1)        (ricerca, export)
```

### 6.2 Componenti nuovi e modificati

| Componente | Stato | Descrizione |
|---|---|---|
| `TranscriptionEngine` (protocollo) | **nuovo** | Astrae `startLive/stopLive/transcribeFile`; `WhisperTranscriber` V1 diventa `WhisperEngine` conforme (codice conservato). |
| `AppleSpeechEngine` | **nuovo** | `SpeechAnalyzer` + `SpeechTranscriber` con `.volatileResults`; gestione `AssetInventory` per il download del modello di sistema (una tantum, gestito dall'OS). |
| `StartDictationIntent: AudioRecordingIntent` | **nuovo** | Avvio in background + Live Activity sincrona in `perform()`. Lo stato vive in `FlowBridgeCoordinator`, non nell'intent (gotcha documentato). Fallback `openAppWhenRun = true` dietro flag. |
| `DictationActivity` (ActivityKit + widget extension) | **nuovo** | Compact: waveform + `Text(timerInterval:)`. Expanded: anteprima transcript live + bottoni Stop / Annulla (`LiveActivityIntent` → processo app). Lock screen incluso. `.supplementalActivityFamilies([.small])` per Watch/CarPlay gratis. |
| `TranscriptPolisher` | **nuovo** | `LanguageModelSession` per-transcript (niente accumulo di contesto), `@Generable` per output strutturato, `prewarm()` all'avvio registrazione, chunking oltre ~2.500 token, fallback totale al grezzo. Toggle utente: Grezzo / Pulito / Pulito+Tono. |
| `VocabularyStore` | **nuovo** | Lista termini utente (nomi, gergo). Iniettata come prompt bias in WhisperKit e `contextualStrings` in DictationTranscriber. **La feature che né Apple né SpeechTranscriber hanno.** |
| Keyboard extension V2 | **upgrade** | Darwin notifications al posto del polling 250ms; diff incrementale del testo invece di delete-all-reinsert (meno flicker); indicatore di stato registrazione. |
| `AudioSafetyBuffer` | **nuovo** | Audio scritto su disco (App Group) durante la registrazione; se app/trascrizione crasha, al riavvio la dettatura si recupera e ritrascrive. Base della garanzia "mai persa una dettatura". |
| Control Center control (`ControlWidgetButton`) | **nuovo** | Piazzabile in Control Center, Lock Screen (al posto della torcia) e sull'Action Button stesso. |
| Widget Home Screen | **nuovo** | Bottone di avvio + ultima trascrizione. |
| Cronologia | **upgrade** | Da "ultimo transcript" a libreria locale con ricerca full-text, pin, export via share sheet. Tutto su disco locale, cifrato dal sistema. |
| `NetworkGuard` | **invariato** | Resta la garanzia fail-closed. In V2 diventa anche claim di marketing verificabile ("l'app non ha capacità di rete sul percorso audio"). |

### 6.3 Gestione memoria e termica

- Un solo motore caricato alla volta; `SpeechTranscriber` non pesa sulla nostra memoria (modello di sistema).
- WhisperKit turbo compresso (626MB) sostituisce Whisper Small **solo per chi attiva il motore Precision**; su iPhone Air i 12GB rendono il co-residente LLM 3B un non-problema. Il TTL di unload V1 (180s) resta.
- Prewarm del Polisher solo a registrazione avviata (il modello è caldo quando serve, mai prima).
- File lunghi (share extension): trascrizione con progresso visibile; accettiamo il throttling termico dell'Air (nessuna vapor chamber) — è un caso d'uso secondario.

---

## 7. Roadmap per fasi

> Stime per uno sviluppatore singolo con AI assist. Ogni fase termina con una build TestFlight utilizzabile quotidianamente ("dogfood gate"): se la fase non migliora l'uso quotidiano reale, non si passa alla successiva.

### Fase 0 — Fondamenta *(1–2 settimane)* — ✅ implementata

| # | Task | Stato |
|---|---|---|
| 0.1 | Protocollo `TranscriptionEngine`; `WhisperTranscriber` → `WhisperEngine` | ✅ `TranscriptionEngine.swift`, `WhisperEngine.swift` |
| 0.2 | Darwin notifications app↔tastiera (sostituisce polling) | ✅ `DarwinNotifier.swift`; polling legacy dietro `keyboardLegacyPollingEnabled`, safety refresh a 2s |
| 0.3 | `AudioSafetyBuffer`: registrazione sempre su disco + recovery al riavvio | ✅ WAV crash-safe nell'App Group, flush 1s, recovery in `bootstrap()` con source `.recovered` |
| 0.4 | Bench harness locale: WER/latency su set di frasi italiane registrate | ✅ `WERCalculator` (testato) + `BenchmarkHarness` su `Resources/Benchmark` |
| 0.5 | Bump `maxRecordingSeconds` 90 → 600 con gestione memoria verificata | ✅ costante aggiornata; budget memoria documentato in ARCHITECTURE.md (~38MB stream + ~19MB WAV) |

*Da fare su device (non possibile in questo ambiente): verifica in Xcode dei target app/keyboard, dogfood del recovery e degli update Darwin, registrazione del set di benchmark italiano. Gli spike `AudioRecordingIntent` e Whisper Mode restano attività da device reale prima della Fase 1.*

### Fase 1 — Il cuore della V2: zero frizione *(3–4 settimane)* → **V2.0** — ✅ implementata in codice (da validare su device)

| # | Task | Stato |
|---|---|---|
| 1.1 | `AppleSpeechEngine` (SpeechTranscriber streaming + AssetInventory) | ✅ `AppleSpeechEngine.swift`; opt-in via `preferredEngine` (Whisper resta default finché il bench 0.4 non decide) |
| 1.2 | `StartDictationIntent: AudioRecordingIntent` — avvio registrazione **senza aprire l'app** | ✅ `Sources/FlowBridgeAppIntents/DictationIntents.swift`; fallback foreground via `ForegroundContinuableIntent`; Live Activity avviata sincrona come richiesto dall'API |
| 1.3 | `DictationActivity`: Dynamic Island compact (waveform+timer) ed expanded (anteprima+Stop) + lock screen | ✅ target `FlowBridgeWidgets` (`DictationLiveActivity.swift`); timer `Text(timerInterval:)` a budget zero; anteprima via update locali dal coordinator |
| 1.4 | `TranscriptPolisher` (FoundationModels): filler via, punteggiatura; grezzo sempre conservato | ✅ `TranscriptPolisher.swift`; guided generation + greedy sampling; fallback al grezzo su ogni errore; prewarm all'avvio registrazione; `rawText` sul record |
| 1.5 | Control Center control + Lock Screen control + widget Home | ✅ `DictationControlWidget.swift` (piazzabile anche sull'Action Button), `FlowBridgeHomeWidget.swift` |
| 1.6 | Onboarding nuovo: 3 schermate (parla → Action Button → tastiera con spiegazione Full Access onesta) | ✅ `OnboardingView.swift`, permessi contestuali |
| 1.7 | Frase Siri via App Shortcuts | ✅ "Dictate with FlowBridge" su `StartDictationIntent` (pronto per Siri AI di iOS 27) |

*Note di implementazione: `AppleSpeechEngine` e `TranscriptPolisher` sono scritti contro la superficie API documentata di iOS 26 (SpeechAnalyzer / FoundationModels) e vanno validati con l'SDK in Xcode — questo ambiente compila solo il framework condiviso (Linux). Il nuovo target `FlowBridgeWidgets` è definito in `project.yml`: serve `xcodegen generate` per materializzarlo nel progetto Xcode. Lo spike su device di `AudioRecordingIntent` resta il primo test da fare.*

**Definition of done V2.0:** dal click dell'Action Button alla prima parola trascritta < 1,5s (target < 1s); dettatura completa senza mai vedere l'app; testo pulito in clipboard + inseribile da tastiera; zero dettature perse in 2 settimane di dogfood.

### Fase 2 — Le cose che nessun locale ha *(3–4 settimane)* → **V2.1** — ✅ implementata in codice (da validare su device)

| # | Task | Stato |
|---|---|---|
| 2.1 | `VocabularyStore` + UI ("Il mio vocabolario"): prompt bias WhisperKit | ✅ store condiviso testato + editor in Settings + `vocabularyPromptTokens` in `WhisperEngine` (bias su file e live). `contextualStrings` per DictationTranscriber: quando aggiungeremo quel modulo |
| 2.2 | Motore "Precision" selezionabile | ✅ `WhisperModelLocator` + variante `.precision` (cartella in Application Support, **nessun download runtime** — bundle/sideload esplicito, coerente con la postura offline); fallback automatico al bundled |
| 2.3 | Tono per-contesto | ✅ ma con correzione di rotta: le tastiere **non possono leggere il bundle id dell'app host** (API pubblica) → il tono si inferisce dai trait del campo di testo (return key "send" → casual, campo email → formal), spesso un segnale migliore. `ToneContextStore` + hint dalla tastiera + default utente |
| 2.4 | Cronologia: libreria locale con ricerca, pin, export | ✅ `TranscriptHistoryStore` (cap 200, i pin non vengono mai evitti, testato) + `HistoryView` (ricerca, copia, copia verbatim, share, pin, delete) |
| 2.5 | Keyboard V2: diff incrementale, tono, "Inserisci e invia" | ✅ diff a prefisso comune (il testo committato non sfarfalla mai), hint di tono, tasto ↵; "ritrascrivi con Precision" rinviato (richiede retention audio, v. backlog) |
| 2.6 | Localizzazione completa IT/EN | ⏳ da fare in Xcode (String Catalog) |

### Fase 3 — Lancio e superfici estese — parzialmente implementata

| # | Task | Stato |
|---|---|---|
| 3.1 | Live Activity su Watch Smart Stack + CarPlay | ✅ `.supplementalActivityFamilies([.small])` |
| 3.2 | Comandi vocali essenziali | ✅ `VoiceCommandProcessor` deterministico IT/EN (punto, virgola, a capo, nuovo paragrafo, punti interrogativo/esclamativo, due punti, punto e virgola), testato, toggle in Settings |
| 3.3 | Paywall + IAP una tantum | ⏳ richiede App Store Connect (prodotti, prezzi): da fare al momento del lancio |
| 3.4–3.6 | Materiale App Store, SEO, TestFlight | ⏳ attività di lancio, non di codice |

**Extra implementati dalle killer feature** (oltre roadmap): Session Append (#4, finestra configurabile, default 5 min), statistiche "Tempo restituito" (#20, `DictationStatsStore` locale + sezione in Settings), vocabolario aptico (#UX §2.2, `HapticPlayer`), sezione Privacy verificabile in Settings.

*(La tabella originale della Fase 3 è stata assorbita nella tabella di stato qui sopra.)*

### Dopo la V2 (backlog esplicito, non promesso)

- Parakeet v3 (licenza Argmax Pro o port CoreML community) se i bench lo giustificano.
- App companion macOS (il mercato Mac della dettatura locale è validato da MacWhisper/Superwhisper).
- Modalità "comando" (editing vocale del testo) — solo dopo che la dettatura base è impeccabile.
- Adapter LoRA custom per Foundation Models (toolkit Apple) — oggi il prompting basta; gli adapter vanno riaddestrati a ogni update dell'OS (~160MB, Background Assets): costo di manutenzione non giustificato.

---

## 8. Cosa NON faremo (non-goals)

Il mandato è "poche cose fatte bene". Quindi, esplicitamente **no** a:

1. **Qualsiasi cloud** — niente sync, niente account, niente analytics remoti, niente "Privacy Mode" ipocrita. Il `NetworkGuard` resta e diventa argomento di marketing.
2. **Android / Windows** — il vantaggio competitivo è la profondità d'integrazione iOS; diluirlo lo azzera.
3. **Trascrizione di riunioni / diarizzazione speaker** — mercato diverso (Granola, ecc.), job diverso. SpeakerKit esiste in argmax-oss se mai servisse, ma non è la V2.
4. **Chat/assistente generalista** — non siamo Siri e non vogliamo esserlo: siamo il layer voce→testo che Siri non fa bene.
5. **Riscrittura AI pesante del contenuto** ("trasforma in email formale") — il Polisher *pulisce*, non riscrive: a 3B parametri le riscritture allucinano, e il nostro utente vuole le *sue* parole, pulite.
6. **Registrazione sempre attiva / wake word** — vietata dalle regole iOS (2.5.4) e contraria al posizionamento privacy.
7. **Abbonamento** — v. §9.

---

## 9. Monetizzazione

**Modello: acquisto una tantum, hard paywall dopo trial.**

- **Trial**: 7 giorni completi (o N dettature) — hard paywall converte ~5× il freemium (RevenueCat 2026) e il freemium eterno svaluta la categoria.
- **FlowBridge Pro — €29,99 una tantum** (fascia da calibrare €19,99–39,99): tutto incluso — motore Precision, vocabolario, tono per-app, cronologia illimitata.
- Ancoraggio comunicativo: *"Wispr Flow costa $180/anno, per sempre. FlowBridge costa come due mesi di Wispr, una volta sola — perché non abbiamo server da pagare con la tua voce."*
- Superwhisper lifetime a $249,99 fa da tetto di riferimento: siamo drasticamente sotto, con integrazione iOS superiore.
- Eventuale "pay once per major version" (stile Things) se in futuro servirà revenue ricorrente — non ora.
- Costo marginale ~zero (nessuna inferenza server) → il modello regge economicamente in modo strutturale, cosa impossibile per i competitor cloud.

---

## 10. Rischi e mitigazioni

| Rischio | Probabilità | Impatto | Mitigazione |
|---|---|---|---|
| **Apple sherlocka la dettatura** (AFM dictation iOS 27) | Alta | Medio | La dettatura migliorata Apple è gated ai device 12GB+ e resta senza vocabolario custom, cronologia, tono per-app, trigger istantanei. Il moat è il *workflow*, non il WER. Monitorare ogni beta. |
| **`AudioRecordingIntent` inaffidabile in alcuni contesti** (errori segnalati nei forum) | Media | Alto (è la feature bandiera) | Prototipo di validazione *prima* di Fase 1 (spike di 2 giorni su device reale); fallback `openAppWhenRun=true` sempre pronto dietro flag; il flusso resta comunque migliore della concorrenza locale. |
| **App Review** su background recording (2.5.4) e Full Access | Media | Medio | Live Activity sempre visibile durante la registrazione (obbligo API che gioca a nostro favore: attribuzione chiara), note di review dettagliate, metadata trasparente come già in V1. |
| **Guardrail Foundation Models** blocca dettature legittime (mediche/legali) | Media | Medio | Fallback automatico e silenzioso al transcript grezzo: l'utente non perde mai testo. |
| **Wispr con $260M** accelera su iOS | Alta | Medio | Non competere su "AI everything": competere su fiducia (locale verificabile), latenza (zero rete) e prezzo (una tantum). Wispr *non può* diventare locale senza rifare l'azienda. |
| **Dimensione app** con Whisper turbo bundled | Bassa | Basso | Motore Precision on-demand (download con consenso) o variante bundle; SpeechTranscriber di default = app base leggerissima. |
| **Termica iPhone Air** su file lunghi | Bassa | Basso | Progress UI, aspettative oneste; il caso d'uso primario (burst brevi) non è impattato. |

---

## 11. Metriche di successo

Tutte misurabili **in locale** (nessuna telemetria remota — coerenza col posizionamento; le metriche di prodotto si raccolgono da TestFlight feedback e dogfood):

| Metrica | Baseline V1 | Target V2 |
|---|---|---|
| Tempo Action Button → prima parola trascritta | ~3–5s (apre l'app, carica Whisper) | **< 1,5s** (senza aprire l'app) |
| Tempo stop → testo pulito pronto | ~1–2s (grezzo) | < 2s (pulito con LLM, prewarmed) |
| Dettature perse (crash, interruzioni) | possibile | **0** (AudioSafetyBuffer: sempre recuperabili) |
| WER italiano (set di test interno) | Whisper Small (~7–9% atteso) | **≤ 4,5%** (SpeechTranscriber) |
| Durata massima dettatura | 90s | 10 min |
| Passi utente per dettare in un'altra app | 4 (apri app, detta, cambia app, inserisci) | **2** (click fisico, stop dall'isola) |
| Rating App Store | n/a | ≥ 4,6 con affidabilità come tema ricorrente delle recensioni |

---

## 12. Fonti principali

*Selezione delle ~70 fonti consultate (luglio 2026).*

**Competitor e mercato**
- Wispr Flow: pricing/changelog — https://wisprflow.ai/pricing · https://wisprflow.ai/whats-new · funding: https://techcrunch.com/2025/11/20/as-its-voice-dectation-app-takes-off-wispr-secures-25m-from-notable-capital/ · https://www.bloomberg.com/news/articles/2026-05-12/ai-dictation-startup-wispr-in-funding-talks-at-2-billion-value
- Superwhisper — https://superwhisper.com/changelog · recensioni iOS: https://apps.apple.com/us/app/superwhisper-ai-dictation/id6471464415
- Willow — https://techcrunch.com/2025/11/12/willows-voice-keyboard-lets-you-type-across-all-your-ios-apps-and-actually-edit-what-you-said/ · Aqua — https://spokenly.app/blog/aqua-voice-pricing · VoiceInk — https://github.com/Beingpax/VoiceInk · Aiko — https://sindresorhus.com/aiko · Whisper Memos — https://whispermemos.com/
- Dettatura Apple iOS 27 (gated 12GB+) — https://9to5mac.com/2026/06/12/ai-advanced-dictation-preview-ios-27-beta/ · lamentele dettatura — https://forums.macrumors.com/threads/why-is-ios-voice-dictation-so-awful.2467556/
- Siri/Gemini — https://www.cnbc.com/2026/01/12/apple-google-ai-siri-gemini.html · https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/
- Subscription economy — https://www.revenuecat.com/state-of-subscription-apps/ · https://adapty.io/blog/9-subscription-trends-dominating-2025/

**Piattaforma iOS**
- ActivityKit / Live Activities — https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities · HIG: https://developer.apple.com/design/human-interface-guidelines/live-activities · interattività: https://developer.apple.com/documentation/WidgetKit/adding-interactivity-to-widgets-and-live-activities
- **AudioRecordingIntent** (la chiave della V2) — https://developer.apple.com/documentation/AppIntents/AudioRecordingIntent · LiveActivityIntent — https://developer.apple.com/documentation/AppIntents/LiveActivityIntent
- Background audio (solo continuazione, mai avvio) — https://developer.apple.com/forums/thread/65604 · https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- Control Center controls — https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- App Intents iOS 26 (interactive snippets, ecc.) — https://developer.apple.com/videos/play/wwdc2025/275/
- Keyboard extension: no mic (verbatim Apple) — https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html · enforcement runtime: https://developer.apple.com/forums/thread/742601 · memoria ~70MB: https://docs.keyboardkit.com/documentation/keyboardkit/developer-memory-management/ · openURL rotto iOS 18: https://keyboardkit.com/blog/2024/09/11/ios18-breaks-selector-based-url-opening
- SpeechAnalyzer/SpeechTranscriber — https://developer.apple.com/videos/play/wwdc2025/277/ · https://developer.apple.com/documentation/speech/speechtranscriber · velocità vs Whisper: https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/ · WER italiano 4,0%: https://dicta.to/blog/speech-to-text-engine-comparison-mac-2026/ · gap vocabolario: https://www.argmaxinc.com/blog/apple-and-argmax
- DictationTranscriber (contextualStrings) — https://developer.apple.com/documentation/speech/dictationtranscriber
- Foundation Models — https://developer.apple.com/documentation/FoundationModels · lingue (italiano ✅): https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models · contesto 4096: https://developer.apple.com/forums/thread/806542 · adapter: https://developer.apple.com/apple-intelligence/foundation-models-adapter/
- WhisperKit / argmax-oss-swift v1.0 — https://github.com/argmaxinc/WhisperKit · compressione 626MB e WER streaming: https://arxiv.org/html/2507.10860v1 · Parakeet v3 (italiano): https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
- iPhone Air (12GB, A19 Pro, termica) — https://www.apple.com/iphone-air/specs/ · https://www.gsmarena.com/apple_iphone_air-review-2885p5.php
