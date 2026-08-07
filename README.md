# 🎵 Mood Player

Une application mobile Flutter qui organise vos playlists musicales par "mood" (ambiance) en utilisant l'API Gemini pour classifier automatiquement chaque morceau.

## 🚀 Fonctionnalités

- **Classification automatique par mood** : Utilise l'API Gemini pour analyser et classifier chaque morceau
- **Moods supportés** : Énergique, Chill, Mélancolique, Festif, Romantique, Concentration, Motivant, Triste
- **Cache local** : Stockage des classifications pour éviter les appels API répétés
- **Lecteur audio** : Lecture avec contrôles depuis la notification/lock screen Android
- **Filtrage et recherche** : Filtrer par mood, rechercher par titre/artiste

## 📁 Structure du projet

```
mood_player/
├── lib/
│   ├── main.dart                    # Point d'entrée principal
│   ├── models/
│   │   └── track.dart               # Modèle de données Track avec Isar
│   ├── services/
│   │   ├── gemini_service.dart      # Service d'appel API Gemini
│   │   ├── storage_service.dart     # Service de stockage local Isar
│   │   └── audio_handler.dart       # Gestionnaire audio pour playback
│   ├── providers/
│   │   ├── providers.dart           # Export des providers
│   │   ├── track_provider.dart      # Providers Riverpod pour les tracks
│   │   └── audio_provider.dart      # Providers Riverpod pour l'audio
│   └── features/
│       ├── home/
│       │   └── home_screen.dart     # Écran principal avec liste
│       ├── player/
│       │   └── player_screen.dart   # Écran du lecteur audio
│       └── tracks/                  # (pour extensions futures)
├── .env                             # Variables d'environnement (non versionné)
└── pubspec.yaml                     # Dépendances du projet
```

## 🛠️ Stack technique

| Composant | Technologie |
|-----------|-------------|
| Framework | Flutter (Dart) |
| Gestion d'état | Riverpod |
| Stockage local | Isar |
| Réseau | Dio |
| Audio | just_audio + audio_service |
| API IA | Gemini |
| Config | flutter_dotenv |

## 📋 Prérequis

1. Flutter SDK ≥ 3.11.1
2. Android Studio / VS Code avec extensions Flutter
3. Compte Google Cloud avec API Gemini activée
4. Clé API Gemini

## ⚙️ Configuration

### 1. Cloner et installer les dépendances

```bash
cd mood_player
flutter pub get
```

### 2. Configurer la clé API

Créez le fichier `.env` à la racine du projet :

```env
GEMINI_API_KEY=votre_cle_api_ici
APP_NAME=Mood Player
```

### 3. Générer le code Isar

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Lancer l'application

```bash
flutter run
```

## 🎯 Utilisation

### Ajouter un morceau
1. Appuyez sur le bouton `+` ou l'icône dans l'AppBar
2. Entrez le titre, l'artiste et (optionnellement) l'album
3. Le morceau est ajouté à la liste

### Classifier un morceau
- Appuyez sur l'icône ✨ à côté d'un morceau non classifié
- Ou utilisez "Classifier tous les morceaux" dans le menu

### Filtrer par mood
- Utilisez les puces de filtre en haut de l'écran
- Combinez avec la recherche pour un filtrage précis

### Écouter un morceau
- Appuyez sur un morceau pour ouvrir le lecteur
- Contrôles disponibles : play/pause, avancer/reculer 10s

## 🔧 Architecture

### Modèle de données (Track)
```dart
@collection
class Track {
  Id id = Isar.autoIncrement;
  late String title;
  late String artist;
  String? album;
  String? filePath;
  MoodType? mood;
  double? moodConfidence;
  DateTime? lastClassified;
}
```

### Service Gemini
- Construit un prompt de classification
- Appelle l'API Gemini
- Parse la réponse JSON
- Gère les erreurs et retries

### Service Storage
- CRUD complet pour les morceaux
- Recherche par titre/artiste
- Filtrage par mood
- Statistiques par mood

## 📝 Notes

- **Pas de backend** : Tout est géré côté client
- **Pas d'authentification** : Application personnelle
- **Clé API** : Ne jamais commiter le fichier `.env`
- **API Gemini** : Vérifiez les quotas et tarifs

## 🐛 Dépannage

### Erreur "GEMINI_API_KEY not found"
- Vérifiez que le fichier `.env` existe
- Vérifiez que `dotenv.load()` est appelé dans `main()`

### Erreur Isar
- Relancez `dart run build_runner build --delete-conflicting-outputs`
- Supprimez le dossier `.dart_tool` si nécessaire

### Erreur audio
- Vérifiez les permissions audio dans `AndroidManifest.xml`
- Testez avec un fichier audio local

## 📄 Licence

Projet personnel - Pas destiné à la publication.