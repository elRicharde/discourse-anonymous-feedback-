# Discourse Anonymous Feedback & White Board

This Discourse plugin provides two independent, anonymous posting forms: "Anonymous Feedback" and "White Board". Both forms are protected by a "door code" (a simple password) and allow users without an account to send a private message to a pre-configured user group.

Technically, posts are submitted via a webpage without requiring a login, and can even be used in a private browsing tab. There is no possibility of tracing back the sender, as IP addresses are not logged. This plugin is designed to offer a secure and confidential channel for communication.

## Why Use This Plugin?

In many communities, sensitive topics or ideas require a channel for feedback that guarantees anonymity and reduces social pressure. This plugin addresses several key challenges:

-   **Fostering Uninhibited Feedback**: It provides a safe space for users (and even non-users, if the door code is shared externally) to share honest, unfiltered opinions, concerns, or innovative ideas without fear of judgment or repercussions. This can lead to more candid and valuable input that might otherwise be withheld.
-   **Confidentiality and Trust**: By ensuring anonymity through technical measures (like HMAC-based rate limiting without IP logging), the plugin builds trust and encourages broader participation, especially for delicate subjects.
-   **Bridging Communication Gaps**: It creates an accessible communication bridge for individuals who are hesitant to post publicly or who do not have a Discourse account, thereby expanding the reach of community engagement.
-   **Structured Input**: By directing feedback to a specific private group, it ensures that sensitive information is reviewed by the appropriate team members, allowing for focused discussion and action away from public view.
-   **Simplicity for Non-Users**: The door code mechanism allows external parties or temporary visitors to provide input without the overhead of full account registration.

Ultimately, this plugin enhances community interaction by enabling a more inclusive and secure environment for critical discussions and suggestions.

## Example Use Cases / Workflows

This plugin was designed to be flexible. Here are two common workflows you can implement:

### Use Case 1: The "White Board" - A Moderated Public Notice Board

This use case is for creating visibility for sensitive topics or inappropriate behavior that has been observed in the community (e.g., at events or in general interactions). For instance, making visible issues like sexism.

**The Goal**: To make important issues visible to the community without exposing the identity of the person reporting them. The focus is on the message, not the sender, and potentially not even on the individuals involved. A simple representation of situations with inappropriate behavior, without naming names, still creates visibility and raises awareness.

**The Workflow**:
1.  **Submission**: A user submits a post via the `/white-board` form. This can be accessed by members (MG), apprentices (ANW), and facilitators (FM). Only the USER "Anonymous" can create posts.
2.  **Private Review**: The post arrives as a Private Message to the configured `target_group` (e.g., a moderation team or a "Trust & Safety" committee). It will be identifiable as a "White Board" entry.
3.  **Vetting**: The team reviews the submission against pre-defined criteria (e.g., no personal attacks, no insults, adherence to community guidelines).
4.  **Publication (If Approved)**: An admin is invited to the message who converts it into a public topic in a dedicated, public "White Board" category. This topic is posted using a specific, generic account (e.g., a "WhiteBoardBot" or "Anonymous" user, configured via the `bot_username` setting). The login details for this user can be shared with the reviewing group. The publication is done by the USER "Anonymous".
5.  **Discussion Control**: The "White Board" category permissions are set so that it is visible to members/apprentices/facilitators but not commentable. Regular forum moderators are expected not to moderate this specific area; this is solely the responsibility of the designated `target_group`. There is still the question of whether the White Board should contain sub-categories (e.g., "anonymous closed" or categories specifically for `target_group` posts).
6.  **Handling Rejections**: Since there is no way to contact the anonymous sender, it's a good practice to have a pinned topic in the "White Board" category explaining the publication criteria and the reasons why a submission might be rejected. Rules justifying non-publication should always be made public in one place in the forum.

### Use Case 2: Anonymous Feedback - A Direct, Private Channel

This use case is for providing a direct, confidential line of communication to a specific team for any kind of feedback (e.g., for voting feedback or other anonymous suggestions).

**The Goal**: To give members and non-members a safe way to provide feedback on community matters, votes, or other topics directly to the leadership or a relevant committee.

**The Workflow**:
1.  **Submission**: A user submits feedback via the `/anonymous-feedback` form. The subject line can help categorize the message. This post arrives with the subject prefix "Anonymous Message - dd.mm.yyyy, hh:mm:ss" to the `target_group`'s collective inbox.
2.  **Private Delivery**: The message arrives as a Private Message to the `target_group`. It is identifiable as "Anonymous Feedback" by its subject prefix. The `target_group` then decides what to do with the message.
3.  **Internal Handling**: The team can then discuss the feedback privately, involve other relevant parties if necessary, or decide on a course of action. This feedback might be used for voting feedback or other anonymous suggestions.
4.  **Best Practice for Inappropriate Feedback**: If a submission is inappropriate, the team can simply delete it. You could consider posting a generic, public notice (e.g., in a "News" category) stating that "Feedback received on [Date] was not processed because it violated our community standards for respectful communication." This informs the sender without revealing any details and encourages them to re-submit in a more constructive manner. If it's a post for the White Board (identifiable by no special marking, or possibly a suffix if helpful): the mods are invited to the message, but no one replies to the message. The mods convert the message into a topic in the "White Board" category -> visible to members/apprentices/facilitators and not commentable.

## Deep Dive: Anonymity & Rate Limiting (HMAC)

A core feature of this plugin is the balance between **absolute anonymity** and **protection against abuse** (spam).

### The Problem: Finite IP Addresses
IPv4 addresses consist of a finite set of combinations (approx. 4.3 billion).
-   **The Risk**: Hashing functions (like SHA256) are irreversible one-way functions. However, if we simply stored `SHA256(IP_Address)`, an attacker (or admin) could pre-calculate the hashes for *all* existing IP addresses (a "Rainbow Table") in seconds. By comparing the stored hash with their list, they could immediately reveal the original IP.

### The Solution: HMAC with a Rotating Secret
We use HMAC (Hash-Based Message Authentication Code). This combines the message (IP) with a cryptographic **Secret Key** before hashing.
-   **The Mechanism**: `Identifier = HMAC(IP_Address + Secret_Key)`
-   **Why it works**: Even though the attacker knows all possible IP addresses, they do **not** know the `Secret Key`. Without this key, they cannot pre-calculate the hashes. The "Rainbow Table" attack becomes impossible because the secret variable is missing.

### Forward Secrecy (Key Rotation)
The `Secret Key` is rotated automatically (e.g., every 4 hours).
-   **Scenario**: Imagine the server is hacked and the attacker steals the *current* Secret Key and the database.
-   **Protection**: Because the key changes regularly and old keys are **permanently discarded**, the attacker can only calculate IP hashes for the *current* time window (e.g., the last 4 hours). All activities from yesterday or last week were hashed with keys that no longer exist. This ensures **Forward Secrecy**: past anonymity cannot be broken, even if the current system is compromised.

### Fast vs. Slow Rotation
You can configure the rotation interval (`hmac_rotation_hours`).
-   **Fast Rotation (e.g., 1 hour)**:
    -   **Pros**: Maximum anonymity. The window of time where distinct actions can be linked to the same (unknown) actor is very short.
    -   **Cons**: "Memory loss" for rate limiting. When the key rotates, the server "forgets" who has already sent messages. A spammer blocked in Hour 1 is effectively unblocked in Hour 2.
-   **Slow Rotation (e.g., 24 hours)**:
    -   **Pros**: Stronger protection against spam, as blocks persist longer.
    -   **Cons**: Within this 24-hour window, an admin can see that "User X" sent 5 messages, even if they don't know who "User X" is (Linkability).

**Recommendation**: A value between **4 and 12 hours** offers a solid balance.

## Features

-   **Two Independent Endpoints**: Provides `/anonymous-feedback` and `/white-board`, each with its own separate configuration.
-   **Protection via Door Code**: Each form is protected by its own secret door code to prevent spam. The door code is the same for everyone, and the page can also be used in private mode or on parents' computer.
-   **Configurable Target Group**: Messages from each form are sent as a private message to a specific, configurable user group.
-   **One-Time Session**: After a message has been successfully sent, the user is redirected back to the door code screen. They must enter the code again to send another message, which prevents simple multi-post spamming. After sending, you land back on the door code, no multi-post is easily possible.
-   **Anonymity-Preserving Rate Limiting**: Protects against brute-force attacks and spam without logging IP addresses.
-   **Bot Protection**: Contains a hidden honeypot field to catch simple bots.
-   **Custom Sender User**: You can define a bot user for each form so that the private messages appear to be sent by this user (e.g., "FeedbackBot"). The user must exist. If empty, the system user is used by default.
-   **Clean, Modern User Interface**: The forms are based on a reusable Ember.js component for a consistent and clean user experience.

## Installation

Follow the standard guide for installing Discourse plugins: [Install a Plugin](https://meta.discourse.org/t/install-a-plugin/19157).

1.  Add the plugin's repository URL to your `app.yml` file:
    ```yml
    hooks:
      after_code:
        - exec:
            cd: $home/plugins
            cmd:
              - git clone https://github.com/elRicharde/discourse-anonymous-feedback
    ```
2.  Rebuild your container: `cd /var/discourse && ./launcher rebuild app`

## Configuration

After installation, you can configure the plugin in the Discourse admin settings. Search for "anonymous feedback". All settings are independent for the "Anonymous Feedback" and "White Board" forms.

| Setting | Description |
| :--- | :--- |
| `anonymous_feedback_enabled` | Toggles the `/anonymous-feedback` page on or off. |
| `white_board_enabled` | Toggles the `/white-board` page on or off. |
| `... door_code` | The secret password users must enter to access the message form. |
| `... target_group` | The name of the user group that receives the private messages. This group must exist. |
| `... rate_limit_per_hour` | A global limit on how many messages can be sent per hour to prevent abuse. Set to `0` to disable. |
| `... max_message_length` | The maximum number of characters allowed in the message text. |
| `... hmac_rotation_hours` | How often the secret key for rate limiting rotates. A shorter duration resets brute-force locks faster but is slightly less secure. |
| `... bot_username` | Optional. The username of the user who will send the PM. The user must exist. If empty, the system user is used. |

## How It Works (Technical Overview)

The plugin was developed with a focus on anonymity and security.

1.  **Access**: A user navigates to `/anonymous-feedback` or `/white-board`.
2.  **Unlock**: The user must enter the correct door code. The server validates this code.
    -   To prevent brute-force attacks, the server uses a rate-limiting system based on an HMAC hash of the user's IP address and a rotating secret. The IP address itself is never stored.
    -   If the code is correct, the server sets a temporary, one-time usable flag in the user's session.
3.  **Submit**: The user writes and sends their message.
4.  **Create PM**: The server checks the session flag. If valid, it creates a new private message to the configured target group and posts it as the configured bot user (or system user). The session flag is then immediately deleted, so the user has to enter the door code again for any further message.

## Development / Architecture

-   **Backend**: A single Ruby on Rails controller, `AnonymousFeedbackController`, processes all requests for both endpoints. It uses a `kind` method that checks the request path (`/anonymous-feedback` vs. `/white-board`) to determine which configurations to use. This avoids code duplication. A dynamic `setting` helper further simplifies reading the configuration.
-   **Frontend**: The user interface is based on a single, reusable Ember.js component, `<AnonymousFeedbackForm />`.
    -   This component contains the entire HTML, CSS, and Javascript logic for the form's state (unlocking, sending, error handling).
    -   The route templates (`anonymous-feedback.hbs` and `white-board.hbs`) are now extremely simple. They just instantiate this component and pass the correct parameters (e.g., title, API URLs). This DRY (Don't Repeat Yourself) approach makes the frontend code clean and easy to maintain.

---

<a id="deutsche-dokumentation"></a>
# Discourse Anonymes Feedback & White Board

Dieses Discourse-Plugin stellt zwei unabhängige, anonyme Formulare bereit: "Anonymes Feedback" und "White Board". Beide Formulare sind durch einen "Türcode" (ein einfaches Passwort) geschützt und ermöglichen es Benutzern ohne Account, eine private Nachricht an eine vorkonfigurierte Benutzergruppe zu senden.

Technisch werden Beiträge auf einer Webseite ohne Login eingegeben und können auch im privaten Tab verwendet werden. Eine Rückverfolgung des Absenders ist nicht möglich, da IP-Adressen nicht geloggt werden. Dieses Plugin ist darauf ausgelegt, einen sicheren und vertraulichen Kommunikationskanal bereitzustellen.

## Warum dieses Plugin verwenden?

In vielen Communitys erfordern sensible Themen oder Ideen einen Feedback-Kanal, der Anonymität garantiert und sozialen Druck reduziert. Dieses Plugin begegnet mehreren zentralen Herausforderungen:

-   **Förderung ungehemmten Feedbacks**: Es bietet einen sicheren Raum für Benutzer (und sogar Nicht-Benutzer, wenn der Türcode extern geteilt wird), um ehrliche, ungefilterte Meinungen, Bedenken oder innovative Ideen ohne Angst vor Urteilen oder Konsequenzen zu teilen. Dies kann zu offeneren und wertvolleren Beiträgen führen, die sonst möglicherweise zurückgehalten würden.
-   **Vertraulichkeit und Vertrauen**: Durch die Sicherstellung der Anonymität mittels technischer Maßnahmen (wie HMAC-basierter Ratenbegrenzung ohne IP-Protokollierung) schafft das Plugin Vertrauen und fördert eine breitere Teilnahme, insbesondere bei heiklen Themen.
-   **Überbrückung von Kommunikationslücken**: Es schafft eine zugängliche Kommunikationsbrücke für Personen, die zögern, öffentlich zu posten, oder die kein Discourse-Konto besitzen, wodurch die Reichweite des Community-Engagements erweitert wird.
-   **Strukturierte Eingabe**: Durch die Weiterleitung des Feedbacks an eine bestimmte private Gruppe wird sichergestellt, dass sensible Informationen von den entsprechenden Teammitgliedern geprüft werden, was eine fokussierte Diskussion und Maßnahmen abseits der Öffentlichkeit ermöglicht.
-   **Einfachheit für Nicht-Benutzer**: Der Türcode-Mechanismus ermöglicht es externen Parteien oder temporären Besuchern, Beiträge zu leisten, ohne den Aufwand einer vollständigen Kontoregistrierung.

Letztendlich verbessert dieses Plugin die Community-Interaktion, indem es ein inklusiveres und sichereres Umfeld für kritische Diskussionen und Vorschläge schafft.

## Beispiel-Anwendungsfälle / Workflows

Dieses Plugin wurde flexibel gestaltet. Hier sind zwei gängige Workflows, die Sie implementieren können:

### Anwendungsfall 1: Das "Weiße Brett" – Ein moderiertes öffentliches Schwarzes Brett

Dieser Anwendungsfall dient dazu, Sichtbarkeit für sensible Themen oder unangemessenes Verhalten zu schaffen, das in der Community beobachtet wurde (z. B. bei Veranstaltungen oder in allgemeinen Interaktionen). Ein konkretes Beispiel ist das Sichtbarmachen von Sexismus.

**Das Ziel**: Wichtige Anliegen für die Community sichtbar zu machen, ohne die Identität der meldenden Person preiszugeben. Der Fokus liegt auf der Nachricht, nicht auf dem Absender, ggf. auch nicht mal auf die betreffenden Personen. Eine einfache Darstellung von Situationen mit unangebrachtem Verhalten ohne Nennung von Namen schafft dennoch Sichtbarkeit und Sensibilisierung.

**Der Workflow**:
1.  **Einreichung**: Ein Benutzer reicht einen Beitrag über das `/white-board`-Formular ein. Dieses kann von Mitgliedern (MG), Anwärtern (ANW) und Moderatoren (FM) aufgerufen werden. Beiträge kann nur der USER "Anonym" erstellen.
2.  **Private Prüfung**: Der Beitrag trifft als private Nachricht bei der konfigurierten `target_group` ein (z. B. einem Moderationsteam oder einem "HeartCare"-Komitee). Er wird als Eintrag für das "Weiße Brett" erkennbar sein.
3.  **Prüfung**: Das Team prüft die Einreichung anhand vordefinierter Kriterien (z. B. keine namentlichen Anschuldigungen, keine Beleidigungen, Einhaltung der Community-Richtlinien). Die "HeartCare"-Gruppe kann mit mindestens X? Leuten entscheiden, ob der Post als Thread im Thema "Weißes Brett" veröffentlicht wird.
4.  **Veröffentlichung (falls genehmigt)**: Falls genehmigt, wird ein Admin in die Nachricht eingeladen, der die Nachricht in ein öffentliches Thema umwandelt, in einer dedizierten, öffentlichen Kategorie "Weißes Brett". Dieses Thema wird mit einem spezifischen, generischen Konto gepostet (z. B. einem "WhiteBoardBot" oder "Anonym"-Benutzer, der über die `bot_username`-Einstellung konfiguriert wird). Die Logindaten für diesen Benutzer können dem "HeartCare"-Team zur Verfügung gestellt werden. Die Veröffentlichung erfolgt durch USER "Anonym".
5.  **Diskussionssteuerung**: Die Berechtigungen der Kategorie "Weiße Brett" werden so eingestellt, dass sie für Mitglieder, Anwärter und Moderatoren sichtbar, aber nicht kommentierbar ist. Normale Forumsmoderatoren sollen diesen Bereich nicht moderieren, dies obliegt allein der "HeartCare"-Gruppe. Es gibt weiterhin die Frage, ob das "Weiße Brett" in "anonym geschlossen" und weitere Kategorie(n) enthalten soll, zum Beispiel eine Kategorie nur für "HeartCare"-Posts zum "Weißen Brett" (kann auch ein angeheftetes Thema in der Kategorie "Weißes Brett" sein, dann aber Vorsicht: "damit kann HeartCare dann Posten und Antworten im anonymen Bereich").
6.  **Umgang mit Ablehnungen**: Da es keine Möglichkeit gibt, den anonymen Absender zu kontaktieren, ist es eine gute Praxis, ein angeheftetes Thema in der Kategorie "Weiße Brett" zu haben, das die Veröffentlichungskriterien und die Gründe, warum ein Beitrag abgelehnt werden könnte, erläutert. Eine Nichtveröffentlichung muss durch Regeln begründet werden, die immer an einer Stelle im Forum öffentlich gemacht werden.

### Anwendungsfall 2: Anonymes Feedback – Ein direkter, privater Kanal

Dieser Anwendungsfall dient dazu, eine direkte, vertrauliche Kommunikationslinie zu einem bestimmten Team für jede Art von Feedback bereitzustellen (z. B. für Feedback bei Abstimmungen oder andere anonyme Vorschläge).

**Das Ziel**: Mitgliedern und Nicht-Mitgliedern eine sichere Möglichkeit zu geben, Feedback zu Community-Angelegenheiten, Abstimmungen oder anderen Themen direkt an die Leitung oder ein zuständiges Komitee zu geben.

**Der Workflow**:
1.  **Einreichung**: Ein Benutzer reicht Feedback über das `/anonymous-feedback`-Formular ein. Die Betreffzeile kann helfen, die Nachricht zu kategorisieren. Dieser Post kommt mit Betreff "Anonyme Nachricht - tt.mm.jjjj, hh:mm:ss" an das "HeartCare"-Sammelpostfach.
2.  **Private Zustellung**: Die Nachricht trifft als private Nachricht bei der `target_group` ein. Sie ist als "anonymes Feedback" erkennbar. Das "HeartCare"-Team entscheidet dann, was mit der Nachricht geschieht.
3.  **Interne Bearbeitung**: Das Team kann das Feedback dann privat diskutieren, bei Bedarf andere relevante Parteien einbeziehen oder über das weitere Vorgehen entscheiden. Dieses Feedback könnte für Abstimmungen oder andere anonyme Vorschläge genutzt werden.
4.  **Best Practice für unangemessenes Feedback**: Wenn eine Einreichung unangemessen ist, kann das Team sie einfach löschen. Sie könnten in Erwägung ziehen, eine allgemeine, öffentliche Mitteilung zu veröffentlichen (z. B. in einer "Neuigkeiten"-Kategorie), in der es heißt: "Feedback, das am [Datum] eingegangen ist, wurde nicht bearbeitet, da es gegen unsere Community-Standards für respektvolle Kommunikation verstoßen hat." Dies informiert den Absender ohne Details preiszugeben und ermutigt ihn, es auf konstruktivere Weise erneut zu versuchen. Ist es ein Post für das "Weiße Brett" (es hat keine Kennzeichnung und ist somit als Eintrag für das WB erkennbar, evtl. kommt noch ein Suffix hin, wenn euch das hilft): Ihr ladet die Mods mit in die Nachricht ein, aber es wird nicht auf die Nachricht geantwortet, von keinem. Die Mods wandeln die Nachricht in ein Thema in der Kategorie "Weiße Brett" um → sichtbar für Mitglieder/Anwärter/Moderatoren und nicht kommentierbar.

## Detailwissen: Anonymität & Ratenbegrenzung (HMAC)

Ein Kernfeature dieses Plugins ist die Balance zwischen **absoluter Anonymität** und **Schutz vor Missbrauch** (Spam).

### Das Problem: Endliche IP-Adressen
IPv4-Adressen bestehen aus einer endlichen Menge an Kombinationen (ca. 4,3 Milliarden).
-   **Das Risiko**: Hash-Funktionen (wie SHA256) sind nicht umkehrbare Einwegfunktionen. Würden wir jedoch nur `SHA256(IP_Adresse)` speichern, könnte ein Angreifer (oder Admin) in Sekunden die Hashes für *alle* existierenden IP-Adressen vorausberechnen ("Rainbow Table"). Durch Abgleich mit dem gespeicherten Hash ließe sich die ursprüngliche IP sofort aufdecken.

### Die Lösung: HMAC mit rotierendem Geheimnis
Wir verwenden HMAC (Hash-Based Message Authentication Code). Dabei wird die Nachricht (IP) vor dem Hashen mit einem kryptographischen **Geheimen Schlüssel** kombiniert.
-   **Der Mechanismus**: `Bezeichner = HMAC(IP_Adresse + Geheimer_Schlüssel)`
-   **Warum es funktioniert**: Obwohl der Angreifer alle IP-Adressen kennt, kennt er den `Geheimen Schlüssel` **nicht**. Ohne diesen Schlüssel kann er die Hashes nicht vorausberechnen. Der "Rainbow Table"-Angriff ist unmöglich, da die geheime Variable fehlt.

### Forward Secrecy (Schlüsselrotation)
Der `Geheime Schlüssel` wird automatisch ausgetauscht (rotiert), z. B. alle 4 Stunden.
-   **Das Szenario**: Stellen Sie sich vor, der Server wird gehackt und der Angreifer stiehlt den *aktuellen* geheimen Schlüssel und die Datenbank.
-   **Der Schutz**: Da der Schlüssel regelmäßig geändert und der alte **unwiederbringlich gelöscht** wird, kann der Angreifer nur IP-Hashes für das *aktuelle* Zeitfenster (z. B. die letzten 4 Stunden) berechnen. Alle Aktivitäten von gestern oder letzter Woche wurden mit Schlüsseln gehasht, die nicht mehr existieren. Dies garantiert **Forward Secrecy**: Vergangene Anonymität kann nicht gebrochen werden, selbst wenn das System heute kompromittiert wird.

### Schnelle vs. Langsame Rotation
Sie können das Rotationsintervall (`hmac_rotation_hours`) konfigurieren.
-   **Schnelle Rotation (z. B. 1 Stunde)**:
    -   **Vorteil**: Maximale Anonymität. Das Zeitfenster, in dem verschiedene Aktionen demselben (unbekannten) Akteur zugeordnet werden können, ist sehr kurz.
    -   **Nachteil**: "Gedächtnisverlust" bei der Ratenbegrenzung. Wenn der Schlüssel rotiert, "vergisst" der Server, wer schon Nachrichten gesendet hat. Ein Spammer, der in Stunde 1 blockiert wurde, ist in Stunde 2 effektiv wieder freigeschaltet.
-   **Langsame Rotation (z. B. 24 Stunden)**:
    -   **Vorteil**: Stärkerer Schutz vor Spam, da Sperren länger anhalten.
    -   **Nachteil**: Innerhalb dieses 24-Stunden-Fensters kann ein Admin sehen, dass "Benutzer X" 5 Nachrichten gesendet hat, auch wenn er nicht weiß, wer "Benutzer X" ist (Verkettbarkeit).

**Empfehlung**: Ein Wert zwischen **4 und 12 Stunden** bietet eine gute Balance.

## Funktionen

-   **Zwei unabhängige Endpunkte**: Stellt `/anonymous-feedback` und `/white-board` bereit, jeder mit eigener, separater Konfiguration.
-   **Schutz durch Türcode**: Jedes Formular ist durch einen eigenen geheimen Türcode geschützt, um Spam zu verhindern. Der Türcode ist für alle gleich, und die Seite kann auch im privaten Modus oder auf dem Rechner seiner Eltern genutzt werden.
-   **Konfigurierbare Zielgruppe**: Nachrichten aus jedem Formular werden als private Nachricht an eine spezifische, konfigurierbare Benutzergruppe gesendet.
-   **Einmalige Sitzung**: Nachdem eine Nachricht erfolgreich gesendet wurde, wird der Benutzer zum Türcode-Bildschirm zurückgeleitet. Er muss den Code erneut eingeben, um eine weitere Nachricht zu senden, was einfaches Multi-Post-Spamming verhindert. Nach dem Absenden landet man wieder auf dem Türcode-Bildschirm, kein Multi-Post ist so einfach möglich.
-   **Anonymität wahrende Ratenbegrenzung**: Schützt vor Brute-Force-Angriffen und Spam, ohne IP-Adressen zu protokollieren.
-   **Bot-Schutz**: Enthält ein verstecktes Honeypot-Feld, um einfache Bots abzufangen.
-   **Benutzerdefinierter Absender-Benutzer**: Sie können für jedes Formular einen Bot-Benutzer festlegen, sodass die privaten Nachrichten scheinbar von diesem Benutzer gesendet werden (z. B. "FeedbackBot"). Der Benutzer muss existieren. Wenn leer, wird standardmäßig der Systembenutzer verwendet.
-   **Saubere, moderne Benutzeroberfläche**: Die Formulare basieren auf einer wiederverwendbaren Ember.js-Komponente für eine konsistente und saubere Benutzererfahrung.

## Installation

Folgen Sie der Standard-Anleitung zur Installation von Discourse-Plugins: [Ein Plugin installieren](https://meta.discourse.org/t/install-a-plugin/19157).

1.  Fügen Sie die Repository-URL des Plugins zu Ihrer `app.yml`-Datei hinzu:
    ```yml
    hooks:
      after_code:
        - exec:
            cd: $home/plugins
            cmd:
              - git clone https://github.com/elRicharde/discourse-anonymous-feedback
    ```
2.  Bauen Sie Ihren Container neu: `cd /var/discourse && ./launcher rebuild app`

## Konfiguration

Nach der Installation können Sie das Plugin in den Discourse-Admin-Einstellungen konfigurieren. Suchen Sie nach "anonymous feedback". Alle Einstellungen sind für die Formulare "Anonymes Feedback" und "White Board" unabhängig.

| Einstellung | Beschreibung |
| :--- | :--- |
| `anonymous_feedback_enabled` | Schaltet die Seite `/anonymous-feedback` ein oder aus. |
| `white_board_enabled` | Schaltet die Seite `/white-board` ein oder aus. |
| `... door_code` | Das geheime Passwort, das Benutzer eingeben müssen, um auf das Nachrichtenformular zuzugreifen. |
| `... target_group` | Der Name der Benutzergruppe, die die privaten Nachrichten erhalten soll. Diese Gruppe muss existieren. |
| `... rate_limit_per_hour` | Ein globales Limit, wie viele Nachrichten pro Stunde gesendet werden können, um Missbrauch zu verhindern. Auf `0` setzen, um zu deaktivieren. |
| `... max_message_length` | Die maximale Anzahl an Zeichen, die im Nachrichtentext erlaubt sind. |
| `... hmac_rotation_hours` | Wie oft der geheime Schlüssel für die Ratenbegrenzung rotiert. Eine kürzere Dauer setzt Brute-Force-Sperren schneller zurück, ist aber geringfügig weniger sicher. |
| `... bot_username` | Optional. Der Benutzername des Benutzers, der die PN senden wird. Der Benutzer muss existieren. Wenn leer, wird der Systembenutzer verwendet. |
| `... subject_placeholder` | Optional. Platzhaltertext für das Betreff-Eingabefeld. |
| `... message_placeholder` | Optional. Platzhaltertext für das Nachrichten-Eingabefeld. |

## Funktionsweise (Technische Übersicht)

Das Plugin wurde mit Fokus auf Anonymität und Sicherheit entwickelt.

1.  **Zugriff**: Ein Benutzer navigiert zu `/anonymous-feedback` oder `/white-board`.
2.  **Freischalten**: Der Benutzer muss den korrekten Türcode eingeben. Der Server validiert diesen Code.
    -   Um Brute-Force-Angriffe zu verhindern, verwendet der Server ein Ratenbegrenzungssystem, das auf einem HMAC-Hash der IP-Adresse des Benutzers und einem rotierenden Geheimnis basiert. Die IP-Adresse selbst wird niemals gespeichert.
    -   Wenn der Code korrekt ist, setzt der Server ein temporäres, einmalig verwendbares Flag in der Sitzung des Benutzers.
3.  **Absenden**: Der Benutzer schreibt und sendet seine Nachricht.
4.  **PN erstellen**: Der Server prüft das Sitzungs-Flag. Wenn es gültig ist, erstellt er eine neue private Nachricht an die konfigurierte Zielgruppe und postet sie als der konfigurierte Bot-Benutzer (oder Systembenutzer). Das Sitzungs-Flag wird dann sofort gelöscht, sodass der Benutzer für jede weitere Nachricht den Türcode erneut eingeben muss.

## Entwicklung / Architektur

-   **Backend**: Ein einziger Ruby on Rails Controller, `AnonymousFeedbackController`, verarbeitet alle Anfragen für beide Endpunkte. Er verwendet eine `kind`-Methode, die den Anfragepfad (`/anonymous-feedback` vs. `/white-board`) prüft, um zu bestimmen, welche Konfigurationen verwendet werden sollen. Dies vermeidet Code-Duplizierung. Ein dynamischer `setting`-Helfer vereinfacht das Auslesen der Konfiguration zusätzlich.
-   **Frontend**: Die Benutzeroberfläche basiert auf einer einzigen, wiederverwendbaren Ember.js-Komponente, `<AnonymousFeedbackForm />`.
    -   Diese Komponente enthält die gesamte HTML-, CSS- und Javascript-Logik für den Zustand des Formulars (Freischalten, Senden, Fehlerbehandlung).
    -   Die Routen-Templates (`anonymous-feedback.hbs` und `white-board.hbs`) sind jetzt extrem einfach. Sie instanziieren nur noch diese Komponente und übergeben die richtigen Parameter (z. B. Titel, API-URLs). Dieser DRY-Ansatz (Don't Repeat Yourself) macht den Frontend-Code sauber und leicht wartbar.
