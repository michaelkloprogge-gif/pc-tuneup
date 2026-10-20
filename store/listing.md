# Microsoft Store listing - PC Tune-Up - Clean & Undo

Copy these into Partner Center. Screenshots: `store/screenshots/en` (English listing) and `store/screenshots/nl` (Dutch); the other languages use the English ones.

## Properties (all languages)

| Field | Value |
|---|---|
| Category | Utilities & tools |
| Privacy policy URL | https://github.com/michaelkloprogge-gif/pc-tuneup#privacy |
| Website | https://michaelkloprogge-gif.github.io/pc-tuneup/ |
| Support contact | https://github.com/michaelkloprogge-gif/pc-tuneup/issues |
| Copyright | © 2026 Michael Kloprogge |
| Price | Free, all markets |
| System requirements | Windows 10 version 2004 or later, x64 |

## Notes for certification (Submission options)

Restricted capabilities - why they are needed:

- **runFullTrust**: PC Tune-Up is a classic desktop app (Windows Forms). It reads system state (WMI, event logs, the registry, installed programs) to diagnose the PC.
- **allowElevation**: some fixes the user chooses need administrator rights (cleaning Windows Update leftovers, Windows services, scheduled tasks, repairing system files). The app runs as a normal user and only asks for elevation (UAC) when the user clicks "Restart as admin".
- **unvirtualizedResources**: the app changes Windows and per-user settings on the user's request (privacy settings, startup apps, Explorer right-click entries, power settings) and updates programs through winget. With registry/file-system write virtualization these changes would go into the package's private copy and have no effect, so write virtualization is turned off. Every change is logged and can be undone in the app's History page.

Testing: no account or test data needed. Start the app; "Show all tools" opens all pages. The app does not change anything without the user clicking a button and confirming the list first. Updates come from the Store only (the app's own updater is switched off in the Store version).

---

## English (en-us)

**Description**

PC Tune-Up gets a slow or cluttered Windows PC back in shape, whatever the brand. It clears junk files, stops apps that start with Windows, removes pre-installed bloatware, updates your programs, and switches off Windows ads and tracking. It also finds what is really wrong: a crashing add-on, a worn battery, a full drive, a device with a driver problem.

Every suggestion is explained in plain words. You see the list before anything changes, and everything PC Tune-Up changes can be undone on the History page.

Simple view shows one calm screen with three big buttons. "Show all tools" opens 25 pages for those who want more. Security software, VPNs and drivers are never touched.

Free and open source (MIT licence), no ads, no account. Nothing about your PC is sent anywhere. Some fixes need administrator rights - PC Tune-Up asks first.

**Product features**

- Fix my PC: all the safe fixes in one go, with a before-and-after
- Clean junk files, browser caches and Windows Update leftovers
- Stop apps that start with Windows; remove bloatware and trial software
- Update outdated programs with winget
- Switch off Windows ads, tips and tracking
- Crashes, freezes and blue screens explained, with one-click fixes
- Battery wear, drive health, and which upgrades fit your PC
- Every change can be undone
- English, Dutch, German, French, Spanish, Italian and Polish; light and dark theme

**Keywords**: cleaner, bloatware, startup, speed up, privacy, maintenance, uninstaller

---

## Nederlands (nl-nl)

**Beschrijving**

PC Tune-Up maakt een trage of volgelopen Windows-pc weer fris, van welk merk ook. Het ruimt overbodige bestanden op, stopt apps die met Windows meestarten, verwijdert vooraf geïnstalleerde bloatware, werkt je programma's bij en zet reclame en tracking in Windows uit. Het vindt ook wat er echt mis is: een crashende invoegtoepassing, een versleten accu, een volle schijf, een apparaat met een driverprobleem.

Elke suggestie wordt in gewone taal uitgelegd. Je ziet de lijst voordat er iets verandert, en alles wat PC Tune-Up wijzigt kun je ongedaan maken op de pagina Geschiedenis.

De eenvoudige weergave toont één rustig scherm met drie grote knoppen. "Alle hulpmiddelen tonen" opent 25 pagina's voor wie meer wil. Beveiligingssoftware, VPN's en drivers worden nooit aangeraakt.

Gratis en open source (MIT-licentie), zonder reclame, zonder account. Er wordt niets over je pc verstuurd. Sommige oplossingen hebben beheerdersrechten nodig - PC Tune-Up vraagt het eerst.

**Productkenmerken**

- Fix my PC: alle veilige oplossingen in één keer, met een voor-en-na
- Overbodige bestanden, browsercaches en resten van Windows Update opruimen
- Apps die met Windows meestarten stoppen; bloatware en proefsoftware verwijderen
- Verouderde programma's bijwerken met winget
- Reclame, tips en tracking in Windows uitzetten
- Crashes, vastlopers en blauwe schermen uitgelegd, met oplossingen in één klik
- Slijtage van de accu, gezondheid van de schijf en welke upgrades passen
- Elke wijziging kan ongedaan worden gemaakt
- Nederlands, Engels, Duits, Frans, Spaans, Italiaans en Pools; licht en donker thema

**Trefwoorden**: opschonen, bloatware, opstarten, sneller, privacy, onderhoud, verwijderen

---

## Deutsch (de-de)

**Beschreibung**

PC Tune-Up bringt einen langsamen oder vollgemüllten Windows-PC wieder in Form, egal von welcher Marke. Es entfernt überflüssige Dateien, stoppt Apps, die mit Windows starten, entfernt vorinstallierte Bloatware, aktualisiert deine Programme und schaltet Werbung und Tracking in Windows ab. Es findet auch, was wirklich nicht stimmt: ein abstürzendes Add-on, einen verschlissenen Akku, ein volles Laufwerk, ein Gerät mit Treiberproblem.

Jeder Vorschlag wird in einfachen Worten erklärt. Du siehst die Liste, bevor sich etwas ändert, und alles, was PC Tune-Up ändert, kannst du auf der Seite Verlauf rückgängig machen.

Die einfache Ansicht zeigt einen ruhigen Bildschirm mit drei großen Schaltflächen. "Alle Werkzeuge anzeigen" öffnet 25 Seiten für alle, die mehr wollen. Sicherheitssoftware, VPNs und Treiber werden nie angefasst.

Kostenlos und Open Source (MIT-Lizenz), ohne Werbung, ohne Konto. Nichts über deinen PC wird irgendwohin gesendet. Manche Korrekturen brauchen Administratorrechte - PC Tune-Up fragt vorher.

**Produktfeatures**

- Fix my PC: alle sicheren Korrekturen auf einmal, mit Vorher-Nachher
- Überflüssige Dateien, Browser-Caches und Reste von Windows Update entfernen
- Apps stoppen, die mit Windows starten; Bloatware und Testversionen entfernen
- Veraltete Programme mit winget aktualisieren
- Werbung, Tipps und Tracking in Windows abschalten
- Abstürze, Hänger und Bluescreens erklärt, mit Korrekturen per Klick
- Akkuverschleiß, Laufwerkszustand und welche Aufrüstungen passen
- Jede Änderung kann rückgängig gemacht werden
- Deutsch, Englisch, Niederländisch, Französisch, Spanisch, Italienisch und Polnisch; helles und dunkles Design

**Suchbegriffe**: Bereinigung, Bloatware, Autostart, beschleunigen, Datenschutz, Wartung, Deinstallation

---

## Français (fr-fr)

**Description**

PC Tune-Up remet en forme un PC Windows lent ou encombré, quelle que soit sa marque. Il supprime les fichiers inutiles, arrête les applications qui démarrent avec Windows, enlève les logiciels préinstallés superflus, met à jour tes programmes et désactive la publicité et le pistage de Windows. Il trouve aussi ce qui ne va vraiment pas : un module qui plante, une batterie usée, un disque plein, un périphérique avec un problème de pilote.

Chaque suggestion est expliquée simplement. Tu vois la liste avant tout changement, et tout ce que PC Tune-Up modifie peut être annulé depuis la page Historique.

La vue simple affiche un écran calme avec trois grands boutons. « Afficher tous les outils » ouvre 25 pages pour ceux qui en veulent plus. Les logiciels de sécurité, les VPN et les pilotes ne sont jamais touchés.

Gratuit et open source (licence MIT), sans publicité, sans compte. Rien sur ton PC n'est envoyé nulle part. Certaines corrections demandent les droits d'administrateur - PC Tune-Up demande d'abord.

**Fonctionnalités**

- Fix my PC : toutes les corrections sûres en une fois, avec un avant-après
- Nettoyer les fichiers inutiles, les caches des navigateurs et les restes de Windows Update
- Arrêter les applications qui démarrent avec Windows ; supprimer les logiciels superflus et les versions d'essai
- Mettre à jour les programmes obsolètes avec winget
- Désactiver la publicité, les astuces et le pistage de Windows
- Plantages, blocages et écrans bleus expliqués, avec des corrections en un clic
- Usure de la batterie, état du disque et mises à niveau compatibles
- Chaque modification peut être annulée
- Français, anglais, néerlandais, allemand, espagnol, italien et polonais ; thème clair et sombre

**Mots-clés** : nettoyage, bloatware, démarrage, accélérer, confidentialité, entretien, désinstallation

---

## Español (es-es)

**Descripción**

PC Tune-Up pone en forma un PC con Windows lento o desordenado, sea de la marca que sea. Elimina archivos innecesarios, detiene las aplicaciones que se inician con Windows, quita el software preinstalado que sobra, actualiza tus programas y desactiva la publicidad y el rastreo de Windows. También encuentra lo que de verdad falla: un complemento que se bloquea, una batería gastada, un disco lleno, un dispositivo con un problema de controlador.

Cada sugerencia se explica con palabras sencillas. Ves la lista antes de que cambie nada, y todo lo que PC Tune-Up cambia se puede deshacer en la página Historial.

La vista sencilla muestra una pantalla tranquila con tres botones grandes. «Mostrar todas las herramientas» abre 25 páginas para quien quiera más. El software de seguridad, las VPN y los controladores nunca se tocan.

Gratuito y de código abierto (licencia MIT), sin anuncios, sin cuenta. No se envía nada sobre tu PC a ningún sitio. Algunas correcciones necesitan permisos de administrador - PC Tune-Up pregunta antes.

**Características**

- Fix my PC: todas las correcciones seguras de una vez, con un antes y después
- Limpiar archivos innecesarios, cachés de navegadores y restos de Windows Update
- Detener aplicaciones que se inician con Windows; quitar bloatware y versiones de prueba
- Actualizar programas antiguos con winget
- Desactivar la publicidad, los consejos y el rastreo de Windows
- Bloqueos, cuelgues y pantallas azules explicados, con correcciones en un clic
- Desgaste de la batería, estado del disco y qué mejoras encajan
- Cada cambio se puede deshacer
- Español, inglés, neerlandés, alemán, francés, italiano y polaco; tema claro y oscuro

**Palabras clave**: limpiador, bloatware, inicio, acelerar, privacidad, mantenimiento, desinstalar

---

## Italiano (it-it)

**Descrizione**

PC Tune-Up rimette in forma un PC Windows lento o disordinato, di qualsiasi marca. Elimina i file inutili, blocca le app che si avviano con Windows, rimuove il software preinstallato superfluo, aggiorna i tuoi programmi e disattiva pubblicità e tracciamento di Windows. Trova anche cosa non va davvero: un componente aggiuntivo che si blocca, una batteria usurata, un disco pieno, un dispositivo con un problema di driver.

Ogni suggerimento è spiegato in parole semplici. Vedi l'elenco prima che cambi qualcosa, e tutto ciò che PC Tune-Up modifica si può annullare nella pagina Cronologia.

La vista semplice mostra una schermata tranquilla con tre grandi pulsanti. "Mostra tutti gli strumenti" apre 25 pagine per chi vuole di più. Software di sicurezza, VPN e driver non vengono mai toccati.

Gratuito e open source (licenza MIT), senza pubblicità, senza account. Nulla del tuo PC viene inviato da nessuna parte. Alcune correzioni richiedono i diritti di amministratore - PC Tune-Up chiede prima.

**Funzionalità**

- Fix my PC: tutte le correzioni sicure in un colpo solo, con un prima e dopo
- Pulire file inutili, cache dei browser e residui di Windows Update
- Bloccare le app che si avviano con Windows; rimuovere bloatware e versioni di prova
- Aggiornare i programmi obsoleti con winget
- Disattivare pubblicità, suggerimenti e tracciamento di Windows
- Arresti anomali, blocchi e schermate blu spiegati, con correzioni in un clic
- Usura della batteria, stato del disco e quali aggiornamenti hardware sono adatti
- Ogni modifica si può annullare
- Italiano, inglese, olandese, tedesco, francese, spagnolo e polacco; tema chiaro e scuro

**Parole chiave**: pulizia, bloatware, avvio, velocizzare, privacy, manutenzione, disinstallare

---

## Polski (pl-pl)

**Opis**

PC Tune-Up przywraca formę wolnemu lub zagraconemu komputerowi z Windows, niezależnie od marki. Usuwa zbędne pliki, wyłącza aplikacje uruchamiane razem z Windows, usuwa preinstalowane zbędne oprogramowanie, aktualizuje Twoje programy i wyłącza reklamy oraz śledzenie w Windows. Znajduje też to, co naprawdę jest nie tak: wtyczkę, która się zawiesza, zużytą baterię, pełny dysk, urządzenie z problemem sterownika.

Każda sugestia jest wyjaśniona prostymi słowami. Widzisz listę, zanim cokolwiek się zmieni, a wszystko, co zmienia PC Tune-Up, można cofnąć na stronie Historia.

Widok prosty pokazuje jeden spokojny ekran z trzema dużymi przyciskami. "Pokaż wszystkie narzędzia" otwiera 25 stron dla tych, którzy chcą więcej. Oprogramowanie zabezpieczające, VPN-y i sterowniki nigdy nie są ruszane.

Bezpłatny i open source (licencja MIT), bez reklam, bez konta. Nic o Twoim komputerze nie jest nigdzie wysyłane. Niektóre poprawki wymagają uprawnień administratora - PC Tune-Up najpierw pyta.

**Funkcje**

- Fix my PC: wszystkie bezpieczne poprawki naraz, z porównaniem przed i po
- Czyszczenie zbędnych plików, pamięci podręcznej przeglądarek i resztek Windows Update
- Wyłączanie aplikacji startujących z Windows; usuwanie bloatware i wersji próbnych
- Aktualizacja starych programów przez winget
- Wyłączanie reklam, porad i śledzenia w Windows
- Awarie, zawieszenia i niebieskie ekrany wyjaśnione, z poprawkami jednym kliknięciem
- Zużycie baterii, stan dysku i pasujące ulepszenia sprzętu
- Każdą zmianę można cofnąć
- Polski, angielski, niderlandzki, niemiecki, francuski, hiszpański i włoski; jasny i ciemny motyw

**Słowa kluczowe**: czyszczenie, bloatware, autostart, przyspieszenie, prywatność, konserwacja, odinstalowanie
