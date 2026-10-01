# Build e collaudo sul secondo Mac

Usa questo percorso dopo aver installato Xcode 26 o successivo completo. Le PR da provare sono [FlowBridge iPhone #8](https://github.com/MiloMilo2121/FlowBridge/pull/8) (`design-system-macos`) e [FlowBridge Mac #3](https://github.com/MiloMilo2121/trascrittore-auto/pull/3) (`flowbridge-icloud-sync`). Lavora in due checkout nuovi: l'archivio delle call e l'app Mac già installata non vanno sostituiti durante il preflight.

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
./scripts/preflight.sh
```

Il preflight deve completare build Swift, test condivisi, controllo runtime, generazione progetto, build di tutti i target iOS e test su simulatore. La CI della PR ha già passato 63 test; il preflight locale verifica la toolchain del secondo Mac. Controlla che `Resources/WhisperModels/WhisperSmall/` sia nel checkout e nell'archivio finale.

## 3. Firma e dispositivo

In Xcode seleziona un team **Apple Developer Program** attivo per app, tastiera, share e widgets. Verifica che il team possa usare `group.com.marcomilanello.flowbridge` e `iCloud.com.marcomilanello.flowbridge`; la presenza delle stringhe negli entitlement non prova che i profili firmati le autorizzino. Verifica anche un record App Store Connect per `com.marcomilanello.flowbridge`.

Collega l'iPhone 17 Air, abilita Developer Mode se richiesto e installa la build. Esegui la matrice in [TESTFLIGHT_BETA.md](TESTFLIGHT_BETA.md) e registra i tre tempi per cloud, locale, rete assente e primo avvio. La guida non tecnica è [GUIDA_TESTER.md](GUIDA_TESTER.md).

## 4. Diario Mac ↔ iPhone

In un checkout separato di `MiloMilo2121/trascrittore-auto`, passa a `flowbridge-icloud-sync` ed esegui `cd app && ./scripts/costruisci.sh` senza `--installa`. Prima di installare la nuova app sul Mac che registra davvero, verifica firma, entitlement iCloud e percorso dell'archivio. Usa call sintetiche per la prima prova e confronta gli hash del testo originale prima e dopo l'esportazione. Prova creazione simultanea, offline→online, migrazione ripetuta, lapidi, call e conflitti; controlla lo stato su entrambe le app.

## 5. Solo dopo il collaudo

Incrementa `CURRENT_PROJECT_VERSION` in `project.yml`, rigenera il progetto, committa e pubblica il branch. Archivia dall'Organizer di Xcode con firma valida, verifica modello e capability nel `.xcarchive`, carica in App Store Connect, completa le note per la beta review e associa la build al gruppo esterno. Conserva misure, esiti e [video reale](VIDEO_DEMO.md) con il numero di build. Nessun test su simulatore dimostra da solo streaming AssemblyAI, iCloud tra dispositivi o affidabilità con telefono bloccato.
