package com.example.mood_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File

/**
 * Widget d'écran d'accueil : fantôme d'humeur, titre, artiste et commandes.
 *
 * L'app Flutter envoie l'état (voir le canal « widget » de MainActivity) ;
 * il est gardé dans des préférences pour que le widget reste affiché, avec
 * le dernier morceau, même quand l'app est fermée. Les boutons envoient de
 * vraies touches média à audio_service.
 */
class AuraWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    companion object {
        const val PREFS = "aura_widget"
        const val GHOST_FILE = "widget_ghost.png"

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, AuraWidgetProvider::class.java))
            for (id in ids) render(context, mgr, id)
        }

        private fun mediaPending(context: Context, keyCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(
                    context, "com.ryanheise.audioservice.MediaButtonReceiver"
                )
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            return PendingIntent.getBroadcast(
                context, keyCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        private fun render(context: Context, mgr: AppWidgetManager, id: Int) {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val title = p.getString("title", null)
            val artist = p.getString("artist", "") ?: ""
            val mood = p.getString("mood", "") ?: ""
            val playing = p.getBoolean("playing", false)
            val color = p.getInt("color", Color.parseColor("#C94DFF"))

            val views = RemoteViews(context.packageName, R.layout.aura_widget)
            views.setTextViewText(R.id.widget_title, title ?: "Aura")
            views.setTextViewText(
                R.id.widget_artist,
                if (title == null) "Rien en lecture" else artist
            )
            views.setTextViewText(R.id.widget_mood, mood.uppercase())
            views.setTextColor(R.id.widget_mood, color)

            val ghost = File(context.filesDir, GHOST_FILE)
            if (ghost.exists()) {
                BitmapFactory.decodeFile(ghost.path)?.let {
                    views.setImageViewBitmap(R.id.widget_ghost, it)
                }
            }

            views.setImageViewResource(
                R.id.widget_play,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
            )
            views.setOnClickPendingIntent(
                R.id.widget_play, mediaPending(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            )
            views.setOnClickPendingIntent(
                R.id.widget_next, mediaPending(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            )
            views.setOnClickPendingIntent(
                R.id.widget_prev, mediaPending(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            )

            // Toucher le reste du widget ouvre l'app.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val open = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                views.setOnClickPendingIntent(R.id.widget_root, open)
                views.setOnClickPendingIntent(R.id.widget_ghost, open)
            }

            mgr.updateAppWidget(id, views)
        }
    }
}
