# Build e collaudo sul secondo Mac

Usa questo percorso dopo aver installato Xcode 26 o successivo completo. Le PR da provare sono [FlowBridge iPhone #8](https://github.com/MiloMilo2121/FlowBridge/pull/8) (`design-system-macos`) e [FlowBridge Mac #3](https://github.com/MiloMilo2121/trascrittore-auto/pull/3) (`flowbridge-icloud-sync`), con le correzioni della sua review in [#4](https://github.com/MiloMilo2121/trascrittore-auto/pull/4) (`flowbridge-icloud-sync-v1`). Lavora in due checkout nuovi: l'archivio delle call e l'app Mac già installata non vanno sostituiti durante il preflight.

## 1. Preparare Xcode

Apri Xcode una volta, accetta la licenza e installa un runtime iOS Simulator. In Terminale verifica:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
df -h .
```

Servono almeno 10 GiB liberi per il preflight; libera ulteriore spazio prima dell'archivio firmato. Con i soli Command Line Tools `xcodebuild` non funziona.

## 2. Compilare il branch iPhone

In un checkout nuovo di `MiloMilo2121/FlowBridge`, passa al branch `design-system-macos`, poi esegui:

```sh
./scripts/fetch-whisper-small.sh
./scripts/preflight.sh
```

Il modello Whisper (467 MB) è escluso da git, quindi un checkout nuovo non lo contiene: senza il primo comando il build passa ma la dettatura locale sul dispositivo non funziona. Il preflight deve completare build Swift, test condivisi, controllo runtime, generazione progetto, build di tutti i target iOS e test su simulatore. La CI della PR ha già passato 63 test; il preflight locale verifica la toolchain del secondo Mac. Controlla che `Resources/WhisperModels/WhisperSmall/` sia presente anche nell'archivio finale.

## 3. Verificare l'account, poi firmare

Accedi a [Apple Developer Account](https://developer.apple.com/account/) con l'Apple Account che userai in Xcode. In **Membership details** verifica che compaiano un Team ID, il ruolo e una data di rinnovo per **Apple Developer Program**. Se Xcode mostra solo **Personal Team**, puoi installare sul tuo iPhone ma non distribuire tramite TestFlight. Le [istruzioni Apple sugli account](https://developer.apple.com/help/account/basics/about-your-developer-account) distinguono i due casi.

Accedi anche ad [App Store Connect](https://appstoreconnect.apple.com/) e controlla in **Apps** se esiste FlowBridge con bundle ID `com.marcomilanello.flowbridge`. Se la sezione non è accessibile, o l'app non compare, annota esattamente ciò che vedi: l'accesso e il record vanno risolti prima dell'upload. Non inviare password, codici a due fattori o chiavi API nel repository.

In Xcode seleziona un team **Apple Developer Program** attivo per app, tastiera, share e widgets. Verifica che il team possa usare `group.com.marcomilanello.flowbridge` e `iCloud.com.marcomilanello.flowbridge`; la presenza delle stringhe negli entitlement non prova che i profili firmati le autorizzino.

## 4. Dispositivo

Collega l'iPhone 17 Air, abilita Developer Mode se richiesto e installa la build. Esegui la matrice in [TESTFLIGHT_BETA.md](TESTFLIGHT_BETA.md) e registra i tre tempi per cloud, locale, rete assente e primo avvio. La guida non tecnica è [GUIDA_TESTER.md](GUIDA_TESTER.md).

## 5. Diario Mac ↔ iPhone

In un checkout separato di `MiloMilo2121/trascrittore-auto`, passa a `flowbridge-icloud-sync-v1` (la #3 con le correzioni della review). **La build di default del Mac non ha iCloud**: firmati senza un provisioning profile, gli entitlement iCloud fanno uccidere l'app all'avvio, registratore delle call compreso. Con il team Apple Developer, un container registrato e un profilo per `com.marcomilanello.flowbridge.recorder`:

```sh
cd app
FLOWBRIDGE_ICLOUD=1 FLOWBRIDGE_PROFILO=<percorso del .provisionprofile> \
FLOWBRIDGE_IDENTITA="<identità del team>" ./scripts/costruisci.sh
```

senza `--installa`. Lo script controlla prima di compilare che il profilo copra bundle, container, certificato di firma, scadenza e questo Mac. Prima di installare la nuova app sul Mac che registra davvero, verifica firma, entitlement e percorso dell'archivio: un certificato nuovo fa chiedere di nuovo tutti i permessi. Usa call sintetiche per la prima prova e confronta gli hash del testo originale prima e dopo l'esportazione. Prova creazione simultanea, offline→online, migrazione ripetuta, lapidi su entrambi i lati (il testo cancellato non deve tornare nel contenitore), call e conflitti; controlla lo stato su entrambe le app. Le regole che i due lati devono rispettare sono in [CONTRATTO-DIARIO.md](CONTRATTO-DIARIO.md), «Lo specchio su iCloud».

## 6. Solo dopo il collaudo

Incrementa `CURRENT_PROJECT_VERSION` in `project.yml`, rigenera il progetto, committa e pubblica il branch. Archivia dall'Organizer di Xcode con firma valida, verifica modello e capability nel `.xcarchive`, carica in App Store Connect, completa le note per la beta review e associa la build al gruppo esterno. Conserva misure, esiti e [video reale](VIDEO_DEMO.md) con il numero di build. Nessun test su simulatore dimostra da solo streaming AssemblyAI, iCloud tra dispositivi o affidabilità con telefono bloccato.
