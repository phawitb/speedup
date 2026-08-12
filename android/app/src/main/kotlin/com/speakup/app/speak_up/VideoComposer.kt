package com.speakup.app.speak_up

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

@UnstableApi
class VideoComposer(private val context: Context) {
    fun compose(arguments: Map<String, Any?>, callback: (Result<String>) -> Unit) {
        val inputPath = arguments["inputPath"] as? String
            ?: return callback(Result.failure(IllegalArgumentException("The camera video is missing")))
        val input = File(inputPath)
        if (!input.exists() || input.length() == 0L) {
            return callback(Result.failure(IllegalStateException("The camera video is empty")))
        }
        val output = File(context.cacheDir, "speakup-composed-${System.currentTimeMillis()}.mp4")
        val overlay = SpeakUpOverlay(context, arguments)
        val effects = Effects(
            emptyList(),
            listOf(
                Presentation.createForWidthAndHeight(
                    1080,
                    1920,
                    Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP,
                ),
                OverlayEffect(listOf<TextureOverlay>(overlay)),
            ),
        )
        val edited = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input)))
            .setEffects(effects)
            .build()
        val transformer = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (output.exists() && output.length() > 0) {
                        callback(Result.success(output.absolutePath))
                    } else {
                        callback(Result.failure(IllegalStateException("The composed video is empty")))
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    output.delete()
                    callback(Result.failure(exportException))
                }
            })
            .build()
        transformer.start(edited, output.absolutePath)
    }
}

@UnstableApi
private class SpeakUpOverlay(
    private val context: Context,
    private val arguments: Map<String, Any?>,
) : BitmapOverlay() {
    private val width = 1080
    private val height = 1920
    private val half = height / 2
    private val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    private val topic = arguments["topic"] as? String ?: "Speaking practice"
    private val day = (arguments["day"] as? Number)?.toInt() ?: 1
    private val duration = (arguments["durationSeconds"] as? Number)?.toInt() ?: 60
    private val avatarMode = arguments["avatarMode"] as? Boolean ?: false
    private val samples = (arguments["faceSamples"] as? List<*>)
        ?.mapNotNull { it as? Map<*, *> }
        .orEmpty()
    private val background = loadBackground(arguments["avatarBackground"] as? String)
    private val cat = loadCat(arguments["avatarCat"] as? String)
    private val scarf = load("assets/images/avatar/scarf-neutral.png")
    private val scarfColor = when (arguments["avatarScarf"] as? String) {
        "Berry" -> Color.rgb(185, 75, 120)
        "Orange" -> Color.rgb(242, 106, 46)
        "Blue" -> Color.rgb(49, 142, 178)
        else -> Color.rgb(21, 155, 154)
    }
    private var cachedFrame = -1L

    @Synchronized
    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val frame = if (avatarMode) presentationTimeUs / 66_000 else presentationTimeUs / 1_000_000
        if (frame == cachedFrame) return bitmap
        cachedFrame = frame
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        drawTop(canvas, presentationTimeUs)
        if (avatarMode) drawAvatar(canvas, presentationTimeUs)
        return bitmap
    }

    private fun drawTop(canvas: Canvas, timeUs: Long) {
        val paper = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(250, 247, 239) }
        canvas.drawRect(0f, 0f, width.toFloat(), half.toFloat(), paper)
        val grid = Paint().apply {
            color = Color.argb(26, 80, 78, 73)
            strokeWidth = 2f
        }
        for (x in 0..width step 72) canvas.drawLine(x.toFloat(), 0f, x.toFloat(), half.toFloat(), grid)
        for (y in 0..half step 72) canvas.drawLine(0f, y.toFloat(), width.toFloat(), y.toFloat(), grid)

        val ink = Color.rgb(31, 29, 27)
        val bold = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }
        bold.textSize = 64f
        canvas.drawText("Day $day 🔥", 62f, 150f, bold)
        drawRec(canvas, width - 250f, 92f)

        bold.textSize = 56f
        bold.textAlign = Paint.Align.CENTER
        drawCenteredWrapped(canvas, topic, width / 2f, 300f, width - 150f, 66f, bold, 3)

        val elapsed = (timeUs / 1_000_000).toInt()
        val remaining = (duration - elapsed).coerceIn(0, duration)
        bold.textSize = 142f
        bold.typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.NORMAL)
        canvas.drawText("%02d:%02d".format(remaining / 60, remaining % 60), width / 2f, 700f, bold)

        val ratio = if (duration == 0) 0f else remaining.toFloat() / duration
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(222, 213, 232) }
        canvas.drawRoundRect(RectF(125f, 790f, width - 125f, 818f), 14f, 14f, track)
        val progress = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = when {
                ratio <= .15f -> Color.rgb(232, 60, 49)
                ratio <= .35f -> Color.rgb(243, 154, 50)
                else -> Color.rgb(85, 69, 133)
            }
        }
        canvas.drawRoundRect(RectF(125f, 790f, 125f + (width - 250f) * ratio, 818f), 14f, 14f, progress)
    }

    private fun drawRec(canvas: Canvas, x: Float, y: Float) {
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(232, 60, 49)
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }
        canvas.drawRoundRect(RectF(x, y, x + 185f, y + 86f), 43f, 43f, border)
        val red = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(232, 60, 49) }
        canvas.drawCircle(x + 38f, y + 43f, 15f, red)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(31, 29, 27)
            textSize = 45f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        canvas.drawText("REC", x + 68f, y + 59f, text)
    }

    private fun drawAvatar(canvas: Canvas, timeUs: Long) {
        val lower = Rect(0, half, width, height)
        if (background != null) drawCover(canvas, background, lower)
        else canvas.drawRect(lower, Paint().apply { color = Color.rgb(103, 198, 180) })
        val sample = sampleAt((timeUs / 1000).toLong())
        val yaw = number(sample, "yaw")
        val pitch = number(sample, "pitch")
        val roll = number(sample, "roll")
        val leftEye = number(sample, "leftEye", 1f)
        val rightEye = number(sample, "rightEye", 1f)
        val mouth = number(sample, "mouthOpen")
        val smile = number(sample, "smile")
        val size = 930f
        val cx = width / 2f + yaw * 42f
        val cy = half + 500f + pitch * 25f
        canvas.save()
        canvas.rotate(roll * 7f, cx, cy)
        val catRect = RectF(cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2)
        cat?.let { canvas.drawBitmap(it, null, catRect, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)) }
        scarf?.let {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                colorFilter = PorterDuffColorFilter(scarfColor, PorterDuff.Mode.MULTIPLY)
            }
            canvas.drawBitmap(it, null, catRect.apply { offset(0f, size * .38f) }, paint)
        }
        drawFaceDetail(canvas, cx, cy, size, leftEye, rightEye, mouth, smile)
        canvas.restore()
    }

    private fun drawFaceDetail(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        size: Float,
        leftEye: Float,
        rightEye: Float,
        mouth: Float,
        smile: Float,
    ) {
        val coat = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(245, 238, 225, 205) }
        fun eyelid(x: Float, openness: Float) {
            if (openness > .92f) return
            val h = size * .10f * (1f - openness)
            canvas.drawOval(RectF(x - size * .075f, cy - size * .08f, x + size * .075f, cy - size * .08f + h), coat)
        }
        eyelid(cx - size * .115f, leftEye)
        eyelid(cx + size * .115f, rightEye)
        val mouthPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(74, 31, 37) }
        canvas.drawOval(
            RectF(
                cx - size * (.025f + smile * .012f),
                cy + size * .12f,
                cx + size * (.025f + smile * .012f),
                cy + size * (.128f + mouth * .045f),
            ),
            mouthPaint,
        )
    }

    private fun sampleAt(timeMs: Long): Map<*, *>? {
        if (samples.isEmpty()) return null
        val index = (timeMs / 66).toInt().coerceIn(0, samples.lastIndex)
        return samples[index]
    }

    private fun number(sample: Map<*, *>?, key: String, fallback: Float = 0f): Float =
        (sample?.get(key) as? Number)?.toFloat() ?: fallback

    private fun drawCenteredWrapped(
        canvas: Canvas,
        value: String,
        centerX: Float,
        firstBaseline: Float,
        maxWidth: Float,
        lineHeight: Float,
        paint: Paint,
        maxLines: Int,
    ) {
        val words = value.split(Regex("\\s+"))
        val lines = mutableListOf<String>()
        var current = ""
        for (word in words) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(candidate) <= maxWidth || current.isEmpty()) current = candidate
            else {
                lines += current
                current = word
                if (lines.size == maxLines - 1) break
            }
        }
        if (current.isNotEmpty() && lines.size < maxLines) lines += current
        lines.forEachIndexed { index, line ->
            canvas.drawText(line, centerX, firstBaseline + index * lineHeight, paint)
        }
    }

    private fun loadCat(name: String?): Bitmap? = load(
        when (name) {
            "Ginger" -> "assets/images/avatar/cat-ginger.png"
            "Gray" -> "assets/images/avatar/cat-gray.png"
            "Black" -> "assets/images/avatar/cat-black.png"
            "Siamese" -> "assets/images/avatar/cat-siamese.png"
            "Tuxedo" -> "assets/images/avatar/cat-tuxedo.png"
            "Calico" -> "assets/images/avatar/cat-calico-final.png"
            "Brown Tabby" -> "assets/images/avatar/cat-brown-tabby.png"
            else -> "assets/images/avatar/cat-base.png"
        },
    )

    private fun loadBackground(name: String?): Bitmap? = when (name) {
        "Cozy Room" -> load("assets/images/backgrounds/cozy-room.png")
        "Café" -> load("assets/images/backgrounds/cafe.png")
        "Library" -> load("assets/images/backgrounds/library.png")
        "Garden" -> load("assets/images/backgrounds/garden.png")
        "Night City" -> load("assets/images/backgrounds/night-city.png")
        else -> null
    }

    private fun load(path: String): Bitmap? = runCatching {
        context.assets.open("flutter_assets/$path").use(BitmapFactory::decodeStream)
    }.getOrNull()

    private fun drawCover(canvas: Canvas, source: Bitmap, destination: Rect) {
        val sourceRatio = source.width.toFloat() / source.height
        val destinationRatio = destination.width().toFloat() / destination.height()
        val crop = if (sourceRatio > destinationRatio) {
            val wanted = (source.height * destinationRatio).roundToInt()
            Rect((source.width - wanted) / 2, 0, (source.width + wanted) / 2, source.height)
        } else {
            val wanted = (source.width / destinationRatio).roundToInt()
            Rect(0, max(0, (source.height - wanted) / 2), source.width, (source.height + wanted) / 2)
        }
        canvas.drawBitmap(source, crop, destination, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }
}
