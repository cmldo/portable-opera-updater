# Portable Opera Updater

**Opera portatile, sempre aggiornata.** Un updater/installer *portable* per Opera (GX, Developer, Beta, Stable, x86 e x64) scritto in PowerShell, con interfaccia WinForms.

È la versione PowerShell del [Portable Opera Updater](https://github.com/UndertakerBen/PorOperaUpd) di UndertakerBen (C#), di cui mantiene il formato su disco: le installazioni esistenti restano compatibili.

## Cosa fa

- Controlla le versioni disponibili e installa/aggiorna ogni canale in una cartella portable.
- Verifica **dimensione e SHA256** dell'installer con i valori forniti da Opera.
- Gestisce la pagina di avviso di **Zscaler** (HTTP 403 sui `.exe` da CDN): apre il link nel browser, clicchi *Continua*, poi *Riprova*.
- Crea da solo i **launcher** `<cartella> Launcher.exe` (compilati al volo con il `csc.exe` di .NET Framework) con scelta del profilo al primo avvio.
- **Autoaggiornamento** dello script da questo repo (con controllo SHA256 e della sintassi, backup `.bak`).
- Modalità console: `-UpdateAll` aggiorna tutto ciò che è già installato.

## Requisiti

- Windows 10/11 con PowerShell 5.1 (o 7) e .NET Framework 4.x
- `Bin\7zr.exe` ([7-Zip](https://www.7-zip.org/), pubblico dominio) accanto allo script

## Installazione

1. Scarica `Opera-Updater.ps1` e `Opera-Updater.cmd` in una cartella a tua scelta.
2. Crea la sottocartella `Bin` e mettici `7zr.exe`.
3. Doppio clic su `Opera-Updater.cmd` (apre la GUI). Da console: `Opera-Updater.cmd -UpdateAll`.

I pulsanti **x86 / x64** installano il canale corrispondente: verde = aggiornato, rosso = aggiornamento disponibile.

## Struttura su disco

```
<cartella>\
  Opera-Updater.ps1 / .cmd
  Bin\7zr.exe
  Opera Stable x64\          opera.exe, Assets\, <versione>\, Profile.txt, updates\Version.log
  Opera Stable x64 Launcher.exe
  OperaUpdater.log           log di tutto quello che succede
```

Con l'opzione *Cartella separata per ogni versione* ogni canale ha la sua cartella; altrimenti ne viene usata una sola (`Opera`).

## Launcher e profili

Al primo avvio di un launcher compare la scelta del profilo, salvata in `Profile.txt`:

- un solo profilo per tutte le versioni (`<cartella>\profile`)
- un profilo separato per ogni versione (`<cartella>\<canale>\profile`)
- il profilo standard di Opera

Gli argomenti passati al launcher (URL, file, flag) vengono inoltrati a `opera.exe`.

## Zscaler / proxy aziendali

Se il download risponde 403, il programma apre il link nel browser. Clicca *Continua* nella pagina di avviso, annulla il download che parte nel browser e premi *Riprova* nella finestra del programma.

## Autoaggiornamento e rilasci

`Opera-Updater.version` contiene `<versione>|<SHA256>` ed è generato dalla GitHub Action
[`release-meta`](.github/workflows/release-meta.yml): ad ogni push di `Opera-Updater.ps1` riscrive anche
l'URL `$SelfUpdateBase` con quello di questo repo. **Per rilasciare** basta alzare `$ScriptVersion` nello script e fare push su `main`.

Il repo deve essere **pubblico** perché lo script legga i file da `raw.githubusercontent.com`.
Per disattivare il controllo: `-NoSelfUpdate`.

## Note

- Il canale Beta può risultare molto indietro rispetto a Stable/Developer: è ciò che risponde l'API di Opera.
- Nessuna dipendenza esterna a parte `7zr.exe`; gli installer vengono scaricati solo dai server di Opera.

## Crediti e licenza

Basato sul lavoro di [UndertakerBen](https://github.com/UndertakerBen/PorOperaUpd). Licenza [MIT](LICENSE).
