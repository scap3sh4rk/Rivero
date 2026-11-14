package dev.scap3sh4rk.rivero

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * The popup opened from a capture notification: pick a category, optionally
 * type a note, and Add (or Ignore). It is plain Android UI so it appears at
 * once, without starting the whole app; the choice is applied the next time
 * Rivero processes captures (immediately if Rivero is running).
 */
class QuickAddActivity : Activity() {
    private var selected: String? = null
    private val chips = mutableListOf<TextView>()

    // Rivero's "Ink & Sky" dark palette.
    private val surface = Color.parseColor("#18181B")
    private val chipBg = Color.parseColor("#232327")
    private val accent = Color.parseColor("#4EA3F8")
    private val onAccent = Color.parseColor("#04101F")
    private val text = Color.parseColor("#F5F5F7")
    private val muted = Color.parseColor("#A1A1AA")

    private fun dp(v: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics,
    ).toInt()

    private fun pill(color: Int, stroke: Int? = null) = GradientDrawable().apply {
        cornerRadius = dp(24).toFloat()
        setColor(color)
        if (stroke != null) setStroke(dp(1), stroke)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getStringExtra(CaptureNotifier.EXTRA_ID)
        if (id == null) {
            finish()
            return
        }
        val heading = intent.getStringExtra(CaptureNotifier.EXTRA_TITLE) ?: "New payment"
        val message = intent.getStringExtra(CaptureNotifier.EXTRA_TEXT) ?: ""

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#99000000"))
            setOnClickListener { finish() } // tap outside: decide later
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
            background = GradientDrawable().apply {
                setColor(surface)
                cornerRadii = floatArrayOf(
                    dp(28).toFloat(), dp(28).toFloat(), dp(28).toFloat(), dp(28).toFloat(),
                    0f, 0f, 0f, 0f,
                )
            }
            isClickable = true // taps inside do not close the popup
        }
        root.addView(
            card,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ),
        )

        card.addView(TextView(this).apply {
            this.text = heading
            setTextColor(this@QuickAddActivity.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.DEFAULT_BOLD
        })
        card.addView(TextView(this).apply {
            this.text = message
            setTextColor(muted)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            maxLines = 3
            setPadding(0, dp(6), 0, dp(16))
        })

        // Category chips (the same categories as the Log screen).
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for (name in CaptureNotifier.categories(this)) {
            val chip = TextView(this).apply {
                this.text = name
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setPadding(dp(16), dp(10), dp(16), dp(10))
                setTextColor(this@QuickAddActivity.text)
                background = pill(chipBg)
                setOnClickListener { select(name) }
            }
            chips += chip
            row.addView(
                chip,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { marginEnd = dp(8) },
            )
        }
        card.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        })

        val note = EditText(this).apply {
            hint = "Add a note (optional)"
            setHintTextColor(muted)
            setTextColor(this@QuickAddActivity.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            imeOptions = EditorInfo.IME_ACTION_DONE
            maxLines = 1
            isSingleLine = true
            background = pill(chipBg)
            setPadding(dp(16), dp(12), dp(16), dp(12))
        }
        card.addView(
            note,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(16) },
        )

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(20), 0, 0)
        }
        fun button(label: String, filled: Boolean, onTap: () -> Unit) = TextView(this).apply {
            this.text = label
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(14), 0, dp(14))
            setTextColor(if (filled) onAccent else this@QuickAddActivity.text)
            background = if (filled) pill(accent) else pill(Color.TRANSPARENT, Color.parseColor("#36363C"))
            setOnClickListener { onTap() }
        }
        val weight = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        buttons.addView(button("Ignore", false) { decide(id, "ignore", null, null) }, weight)
        buttons.addView(View(this), LinearLayout.LayoutParams(dp(12), 1))
        buttons.addView(
            button("Add", true) {
                decide(id, "accept", selected, note.text?.toString()?.trim()?.ifEmpty { null })
            },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        card.addView(buttons)

        // Keep the card above the keyboard (and the navigation bar). On
        // Android 15 apps draw edge to edge, so adjustResize alone does not
        // move it: lift it by the keyboard's height ourselves.
        root.setOnApplyWindowInsetsListener { _, insets ->
            val bottom = if (Build.VERSION.SDK_INT >= 30) {
                insets.getInsets(WindowInsets.Type.ime() or WindowInsets.Type.navigationBars()).bottom
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetBottom
            }
            (card.layoutParams as FrameLayout.LayoutParams).bottomMargin = bottom
            card.requestLayout()
            insets
        }
        setContentView(root)
    }

    private fun select(name: String) {
        selected = if (selected == name) null else name
        for (chip in chips) {
            val on = chip.text == selected
            chip.background = pill(if (on) accent else chipBg)
            chip.setTextColor(if (on) onAccent else text)
        }
    }

    private fun decide(id: String, action: String, category: String?, note: String?) {
        CaptureNotifier.saveDecision(this, id, action, category, note)
        CaptureNotifier.cancel(this, id)
        val running = RiveroNotificationListener.onQueued
        if (running != null) {
            running.invoke() // Rivero is open in the background: apply now
        }
        Toast.makeText(
            this,
            if (action == "ignore") "Ignored" else "Added to Rivero",
            Toast.LENGTH_SHORT,
        ).show()
        finish()
    }
}
