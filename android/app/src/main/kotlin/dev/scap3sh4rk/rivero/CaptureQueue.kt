package dev.scap3sh4rk.rivero

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Notifications waiting for the app to open. Bank message text is personal,
 * so the queue is stored encrypted (AES-256-GCM, key kept in the Android
 * Keystore and never leaving it). Callers hold [RiveroNotificationListener.LOCK].
 */
object CaptureQueue {
    private const val PREFS = "rivero_ingest"
    private const val KEY_ENC = "queue_enc"
    private const val KEY_PLAIN = "queue" // older versions stored it plain
    private const val ALIAS = "rivero_capture_queue"
    private const val MAX = 500

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val out = c.iv + c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(out, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String {
        val all = Base64.decode(stored, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all, 0, 12))
        return String(c.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
    }

    /** Everything queued (plus anything an older version left in plain text). */
    fun read(context: Context): JSONArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val out = JSONArray()
        prefs.getString(KEY_ENC, null)?.let { stored ->
            try {
                val arr = JSONArray(decrypt(stored))
                for (i in 0 until arr.length()) out.put(arr.get(i))
            } catch (_: Exception) {
                // Key lost (e.g. restored onto another phone): nothing to read.
            }
        }
        prefs.getString(KEY_PLAIN, null)?.let { plain ->
            val arr = JSONArray(plain)
            for (i in 0 until arr.length()) out.put(arr.get(i))
        }
        return out
    }

    /** Saves [queue], keeping only the newest [MAX] entries. */
    fun write(context: Context, queue: JSONArray) {
        val trimmed = JSONArray()
        for (i in maxOf(0, queue.length() - MAX) until queue.length()) trimmed.put(queue.get(i))
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ENC, encrypt(trimmed.toString()))
            .remove(KEY_PLAIN)
            .apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(KEY_ENC)
            .remove(KEY_PLAIN)
            .apply()
    }
}

/**
 * Messages of conversation notifications already taken, so a conversation
 * that updates (each new SMS re-posts the earlier unread ones) is not
 * captured again. Ids only (package, key, time), never message text; the
 * newest [MAX] are kept. Callers hold [RiveroNotificationListener.LOCK].
 */
object Seen {
    private const val PREFS = "rivero_capture_seen"
    private const val KEY = "ids"
    private const val MAX = 400

    /** True if [id] is new (and remembers it). */
    fun add(context: Context, id: String): Boolean {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = JSONArray(p.getString(KEY, "[]"))
        for (i in 0 until ids.length()) if (ids.getString(i) == id) return false
        ids.put(id)
        val kept = JSONArray()
        for (i in maxOf(0, ids.length() - MAX) until ids.length()) kept.put(ids.get(i))
        p.edit().putString(KEY, kept.toString()).apply()
        return true
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}
