import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Transforme n'importe quelle exception en phrase courte et lisible pour
/// l'utilisateur. Le détail technique reste dans les logs (print), jamais
/// à l'écran.
String friendlyError(Object? error) {
  if (error == null) return 'Une erreur est survenue.';
  // Détail technique uniquement dans les logs, jamais à l'écran.
  debugPrint('[erreur] $error');

  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Accès refusé par le service. Réessaie plus tard.';
    }
    if (status == 429) {
      return 'Trop de requêtes pour le moment. Réessaie dans quelques minutes.';
    }
    if (status != null && status >= 500) {
      return 'Le service est momentanément indisponible. Réessaie plus tard.';
    }
    return _networkMessage;
  }
  if (error is SocketException || error is HandshakeException) {
    return _networkMessage;
  }
  if (error is TimeoutException) {
    return 'L\'opération a pris trop de temps. Vérifie ta connexion et réessaie.';
  }
  if (error is PathAccessException || error is FileSystemException) {
    return 'Impossible d\'accéder au fichier. Vérifie les autorisations de l\'app.';
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('permission') || code.contains('denied')) {
      return 'Autorisation refusée. Active-la dans les réglages de l\'app.';
    }
    return 'Une erreur système est survenue. Réessaie.';
  }
  if (error is FormatException) {
    return 'Les données reçues sont illisibles. Réessaie.';
  }
  return 'Une erreur inattendue est survenue. Réessaie.';
}

const String _networkMessage =
    'Connexion impossible. Vérifie ta connexion internet et réessaie.';

/// Affiche une erreur proprement : snackbar flottante, icône, couleur
/// d'erreur, fermable. Remplace le simple `Text(error)` brut.
void showAppError(BuildContext context, String message, {VoidCallback? onRetry}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor: AppTheme.backgroundCardElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
        ),
        duration: const Duration(seconds: 5),
        showCloseIcon: true,
        closeIconColor: AppTheme.textSecondary,
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTheme.bodyMedium,
              ),
            ),
          ],
        ),
        action: onRetry == null
            ? null
            : SnackBarAction(
                label: 'Réessayer',
                textColor: AppTheme.accentPrimary,
                onPressed: onRetry,
              ),
      ),
    );
}
