# 🎵 Aura

Lecteur de musique Android (Flutter) qui range ta bibliothèque par **ambiance** (mood). Chaque morceau est classé automatiquement, d'abord avec les tags du fichier, puis avec l'API Groq pour le reste.

## 🚀 Fonctionnalités

### Ambiances
- **17 ambiances** : Énergique, Chill, Mélancolique, Festif, Romantique, Concentration, Motivant, Triste, Évangélique, Colère, Nostalgique, Sombre, Sommeil, Drôle, Road trip, Spirituel, Classique
- **Classification automatique** : pré-classement local à partir du tag « genre », puis Groq pour les morceaux restants ; les résultats sont mis en cache, aucun appel répété
- **Ambiance secondaire** par morceau (ex. Chill + Nostalgique)
- **Corrections manuelles** : tes corrections servent d'exemples dans le prompt pour que la classification suive ta définition de chaque ambiance
- **Ambiances personnalisées** : crée tes propres moods, ajoute des morceaux avec un pourcentage de correspondance, donne-leur une image
- **Images d'ambiance** : par ambiance, au choix entre l'image d'origine, une illustration d'animé, l'icône seule ou une image importée ; un style peut aussi être appliqué à toutes les ambiances d'un coup
- **Mood live** : propose des ambiances selon l'heure, la météo (ville choisie à la main, via Open-Meteo, sans permission de localisation), le mouvement du téléphone et le casque
- **Journal d'humeur** : note ton humeur (avec une note facultative), vois ce que tu écoutes selon ton état, relis l'historique

### Lecture
- Lecteur avec contrôles dans la notification et sur l'écran de verrouillage, file d'attente modifiable
- **Égaliseur** : préréglages, curseurs par bande et renforcement du volume
- **Volume uniforme** : mesure le volume de chaque morceau une fois, en arrière-plan, puis ajuste le gain à la lecture
- **Paroles** : récupérées sur lrclib (synchronisées quand c'est possible) ou lues depuis des fichiers `.lrc`, recherche manuelle, décalage réglable, taille et alignement du texte
- **Widget** d'écran d'accueil : morceau en cours et fantôme d'humeur

### Bibliothèque et recherche
- Scan de toute la bibliothèque de l'appareil (MediaStore), tous formats
- Recherche par titre/artiste, filtre par ambiance, historique de recherches
- **Recherche par ambiance** : « un truc calme pour réviser » (mots-clés en local, Groq pour les phrases floues, négations comprises)
- **Chat avec la bibliothèque** : demande en langage naturel, l'app sélectionne les morceaux en local et propose de les lire, de les mettre en file ou d'en faire une playlist
- **Doublons** : détecte les morceaux présents en plusieurs exemplaires et propose lequel garder
- Renommage d'un morceau (renomme aussi le fichier sur l'appareil)
- Outils de listes : défilement rapide, bouton ancre vers le morceau en cours, Tout lire / Aléatoire / Trier

### Découvertes
- Ajouts récents, morceaux les plus écoutés, favoris, mixes par période et suggestions déduites de l'écoute
- **Rappels d'écoute** : « Ça te dit de réécouter ? », notification programmée ou pop-up quand l'app est ouverte
- **Bilan du mois** : carte-image partageable (ambiance dominante, top morceaux, heure favorite)

### Sauvegarde sur compte Google
- Connexion avec un compte Google (`google_sign_in`) et sauvegarde dans le dossier caché de l'app dans Drive (`appDataFolder`, scope `drive.appdata`) : invisible dans les fichiers de l'utilisateur
- Sauvegarde manuelle ou automatique (démarrage et mise en arrière-plan), restauration après réinstallation ou sur un autre téléphone
- Garde-fou : une sauvegarde plus complète du compte n'est jamais écrasée sans confirmation

### Partage
- **Paroles en image** : choisis jusqu'à 7 lignes, carte 9:16 (1080 × 1920 px) avec panneau vitré, pochette, titre et artiste
- **Extrait de 20 s en vidéo MP4** : même carte, avec les paroles en karaoké quand elles sont synchronisées, fantôme d'humeur et image du mood en option (encodage natif Android, sans ffmpeg)
- Partage des paroles en texte

### Données
- **Transfert de données** : Profil → « Transfert de données » exporte classifications, favoris, ambiances perso, écoutes et réglages dans un fichier JSON ; l'import (autre téléphone, ou classifications d'une autre personne, hors ligne) retrouve les morceaux par titre + artiste + durée
- **Sauvegarde automatique** dans un dossier de ton choix
- **Mises à jour** : vérifie les releases GitHub, télécharge l'APK et lance l'installation
- Journal de crash natif affiché au lancement suivant un plantage

## 🧭 Navigation

Quatre onglets : **Bibliothèque**, **Découvertes**, **Ambiances**, **Profil**, avec un mini-lecteur partagé.

## 🛠️ Stack technique

| Composant | Technologie |
|-----------|-------------|
| Framework | Flutter (Dart) |
| Gestion d'état | Riverpod |
| Base locale | Isar (morceaux) + petits fichiers JSON (profil, réglages, journaux) |
| Réseau | Dio |
| Audio | just_audio + audio_service |
| Bibliothèque | on_audio_query + permission_handler |
| IA | Groq (API compatible OpenAI) |
| Paroles | lrclib.net |
| Météo | Open-Meteo (sans clé) |
| Notifications | flutter_local_notifications |
| Polices | Inter + Space Grotesk, embarquées dans `google_fonts/` (licence OFL) : rendu identique hors-ligne |

## 📁 Structure du projet

```
lib/
├── main.dart
├── models/        # Track (Isar), moods perso, journal, profil, paroles…
├── providers/     # Providers Riverpod (audio, pistes, thème, mood live…)
├── services/      # Groq, stockage, audio, scan, paroles, sauvegarde, mises à jour…
├── features/      # Écrans : home, library, mood, player, foryou, journal,
│                  #   recap, reminder, share, search, chat, profile, update…
├── widgets/       # Composants réutilisables
├── theme/         # Thème et couleurs par ambiance
└── utils/
android/           # Code natif : encodage vidéo, widget, mesure du volume, crash log, installation des mises à jour
assets/            # Images d'ambiance (photos + animé) et icônes
google_fonts/     # Polices Inter et Space Grotesk (TTF statiques + licences)
test/              # Tests unitaires
```

## 📋 Prérequis

1. Flutter SDK ≥ 3.11.1
2. Android Studio ou VS Code avec les extensions Flutter
3. Compte Groq (console.groq.com) et clé API

## ⚙️ Configuration

### 1. Installer les dépendances

```bash
flutter pub get
```

### 2. Configurer la clé API

Copie `env.json.example` en `env.json` (ignoré par git) et mets-y ta clé :

```json
{ "GROQ_API_KEY": "votre_cle_api_ici" }
```

La clé est injectée à la compilation (`--dart-define-from-file`). `GROQ_BASE_URL` peut aussi être défini pour passer par un proxy.

### 3. Générer le code Isar

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Lancer l'application

```bash
flutter run --dart-define-from-file=env.json
```

## 📦 Release

Build local (code obfusqué) :

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define-from-file=env.json
```

Garde le dossier `build/symbols` de chaque version publiée : il sert à relire les stack traces (`flutter symbolize`).

**Signature** : copie `android/key.properties.example` en `android/key.properties` avec ton keystore. Sans ce fichier, le build retombe sur la clé de debug : ne distribue jamais un tel APK, la signature change d'une machine à l'autre et bloque les mises à jour.

**Publication via GitHub Actions** : pousser un tag `vX.Y.Z` déclenche `release.yml`, qui signe l'APK, le build et crée la Release GitHub (c'est elle que l'app interroge pour se mettre à jour). Secrets à créer dans Settings → Secrets and variables → Actions :

| Secret | Rôle |
|--------|------|
| `KEYSTORE_BASE64` | keystore encodé en base64 |
| `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS` | accès au keystore |
| `GROQ_API_KEY` | clé Groq compilée dans l'APK |
| `GROQ_BASE_URL` | (optionnel) proxy Groq |

`build.yml` lance l'analyse, les tests et un build à chaque push et pull request sur `main`.

### Sauvegarde Google : configuration (une seule fois)
1. Google Cloud Console : créer un projet et activer la **Google Drive API**.
2. Google Auth Platform : écran de consentement « Externe », ajouter les comptes testeurs (tant que l'app est en mode Test), ajouter le scope `.../auth/drive.appdata`.
3. Clients : créer un **ID client Android** par clé de signature, avec le package `com.example.mood_player` et le SHA-1 correspondant (`keytool -list -v -keystore ... -alias ...`). Un client pour la clé de debug, un autre pour la clé de release (celle de `key.properties`, ou du secret `KEYSTORE_BASE64` pour le workflow de release).
4. Erreur « ApiException: 10 » : le package ou le SHA-1 de la clé qui a signé l'APK ne correspond à aucun client.

## 🔐 Permissions Android

Lecture de l'audio (`READ_MEDIA_AUDIO`), notifications, service audio en arrière-plan, alarmes exactes et exclusion de l'optimisation de batterie (rappels), installation d'APK (mises à jour) et accès à tous les fichiers (`MANAGE_EXTERNAL_STORAGE`, uniquement pour lire les `.lrc` rangés à côté de la musique). Les trois dernières conviennent à une distribution par GitHub, mais seraient refusées ou à justifier sur le Play Store.

## 📝 Notes

- **Pas de backend** : tout est géré côté client
- **Pas d'authentification** : application personnelle, les données restent sur l'appareil
- **Clé API** : ne jamais commiter `env.json`. Une clé dans une app mobile reste récupérable ; pour la cacher vraiment, passer par un proxy (`GROQ_BASE_URL`)
- **Données envoyées** : titre et artiste à Groq pour la classification, titre/artiste/durée à lrclib pour les paroles, nom de ville à Open-Meteo pour la météo
- **API Groq** : vérifie les quotas et tarifs

## 🐛 Dépannage

### Erreur « GROQ_API_KEY not found »
- Lance bien l'app avec `--dart-define-from-file=env.json`

### Erreur Isar
- Relance `dart run build_runner build --delete-conflicting-outputs`
- Supprime le dossier `.dart_tool` si nécessaire

### Erreur audio
- Vérifie les permissions audio dans `AndroidManifest.xml`
- Teste avec un fichier audio local

### Plantage au lancement
- L'écran de journal de crash s'affiche au lancement suivant : copie la trace pour la partager

## 📄 Licence

Projet personnel.
