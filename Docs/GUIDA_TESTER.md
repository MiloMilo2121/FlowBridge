# Guida per chi prova FlowBridge su iPhone

## Prima di iniziare

Installa la build TestFlight ricevuta dal gruppo di prova. Alla prima apertura scegli **Locale** per dettare solo sull'iPhone, oppure **AssemblyAI** se vuoi usare una tua chiave API. In questo secondo caso leggi e accetta il consenso prima di inserirla: l'audio della dettatura sarà inviato in tempo reale al servizio AssemblyAI nell'UE. Non condividere la chiave con il gruppo di prova.

Per vedere lo stesso diario del Mac, accedi allo stesso Apple Account su entrambi i dispositivi e attiva iCloud Drive. La sincronizzazione può richiedere tempo; se sei offline, le nuove voci restano sull'iPhone e l'app mostra lo stato del diario. Le call concluse arrivano dal Mac come copia del testo, mentre l'originale resta nell'archivio Mac.

## Prova essenziale

1. Apri FlowBridge, consenti il microfono e avvia una dettatura. Controlla che la Dynamic Island mostri registrazione e parole parziali.
2. Parla per qualche secondo e premi **Stop**. Apri il testo dalla Live Activity o dall'app. Controlla cifre, nomi, negazioni e punteggiatura. Se qualcosa cambia il significato, annota la frase esatta.
3. Attiva la tastiera FlowBridge nelle impostazioni di iOS. Prova a digitare normalmente **senza Full Access**. Se abiliti Full Access, prova a inserire la dettatura in un campo di testo non protetto. Nei campi password iOS può sostituire la tastiera: è previsto.
4. Apri **Diario**: cerca una dettatura, una nota o una call ricevuta dal Mac. Il diario mostra anche se iCloud non è disponibile o se un file ha un conflitto.
5. Se usi il cloud, interrompi la rete a metà di una dettatura di prova. Dopo Stop, il telefono deve completare dal WAV locale con Whisper. Se il recupero fallisce, conserva il WAV e usa **Riprova** nelle impostazioni.

## Cosa comunicare

Per ogni problema indica build TestFlight, modello iPhone, versione iOS, motore scelto, rete presente/assente e passaggi per ripeterlo. Per le tre misure registra ora del tap iniziale, prima parola nella Island e testo pronto dopo Stop; ripeti a freddo, con cloud, in locale e senza rete. Non inviare registrazioni o testi di clienti nel feedback senza il loro permesso.

La beta non è dichiarata pronta finché le prove su dispositivo e il trasferimento Mac ↔ iPhone non sono stati osservati. La checklist tecnica è in [TESTFLIGHT_BETA.md](TESTFLIGHT_BETA.md).
