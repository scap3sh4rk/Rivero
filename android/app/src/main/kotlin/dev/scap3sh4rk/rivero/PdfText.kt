package dev.scap3sh4rk.rivero

import android.content.Context
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File

/**
 * Reads the text of a PDF statement on the phone, row by row (sorted by
 * position, so a table row stays on one line). Nothing leaves the device and
 * the password, if any, is only used to open the file, never stored.
 */
object PdfText {
    /** "text" with the lines, or "error": "password" / "unreadable". */
    fun extract(context: Context, path: String, password: String?): Map<String, String> {
        PDFBoxResourceLoader.init(context.applicationContext)
        return try {
            PDDocument.load(File(path), password ?: "").use { doc ->
                val stripper = PDFTextStripper().apply { sortByPosition = true }
                mapOf("text" to stripper.getText(doc))
            }
        } catch (e: InvalidPasswordException) {
            mapOf("error" to "password")
        } catch (e: Exception) {
            mapOf("error" to "unreadable")
        }
    }
}
