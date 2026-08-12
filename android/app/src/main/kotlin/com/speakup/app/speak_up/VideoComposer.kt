package com.speakup.app.speak_up

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
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
import io.flutter.plugin.common.EventChannel
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

@UnstableApi
class VideoComposer(private val context: Context) {
    @Volatile
    var progressSink: EventChannel.EventSink? = null
    @Volatile
    private var exporting = false

    fun compose(arguments: Map<String, Any?>, callback: (Result<String>) -> Unit) {
        exporting = true
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
                    720,
                    1280,
                    Presentation.LAYOUT_SCALE_TO_FIT,
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
                    exporting = false
                    progressSink?.success(1.0)
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
                    exporting = false
                    output.delete()
                    callback(Result.failure(exportException))
                }
            })
            .build()
        transformer.start(edited, output.absolutePath)
        val progressHolder = androidx.media3.transformer.ProgressHolder()
        val progressRunnable = object : Runnable {
            override fun run() {
                val state = transformer.getProgress(progressHolder)
                if (state != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    progressSink?.success((progressHolder.progress / 100.0).coerceIn(0.0, 0.99))
                }
                if (exporting) {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(this, 180L)
                }
            }
        }
        android.os.Handler(android.os.Looper.getMainLooper()).post(progressRunnable)
    }
}

@UnstableApi
private class SpeakUpOverlay(
    private val context: Context,
    private val arguments: Map<String, Any?>,
) : BitmapOverlay() {
    private val width = 720
    private val height = 1280
    private val half = height / 2
    private val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    private val topic = arguments["topic"] as? String ?: "Speaking practice"
    private val day = (arguments["day"] as? Number)?.toInt() ?: 1
    private val duration = (arguments["durationSeconds"] as? Number)?.toInt() ?: 60
    private val avatarMode = arguments["avatarMode"] as? Boolean ?: false
    private val avatarCat = arguments["avatarCat"] as? String ?: "White"
    private val samples = (arguments["faceSamples"] as? List<*>)
        ?.mapNotNull { it as? Map<*, *> }
        .orEmpty()
    private val background = loadBackground(arguments["avatarBackground"] as? String)
    private val transcriptSegments = (arguments["transcriptSegments"] as? List<*>)
        ?.mapNotNull { it as? Map<*, *> }
        .orEmpty()
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
        drawTranscript(canvas, presentationTimeUs)
        return bitmap
    }

    private fun drawTop(canvas: Canvas, timeUs: Long) {
        val paper = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(250, 247, 239) }
        canvas.drawRect(0f, 0f, width.toFloat(), half.toFloat(), paper)
        val grid = Paint().apply {
            color = Color.argb(26, 80, 78, 73)
            strokeWidth = 2f
        }
        for (x in 0..width step 48) canvas.drawLine(x.toFloat(), 0f, x.toFloat(), half.toFloat(), grid)
        for (y in 0..half step 48) canvas.drawLine(0f, y.toFloat(), width.toFloat(), y.toFloat(), grid)

        val ink = Color.rgb(31, 29, 27)
        val bold = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }
        bold.textSize = 43f
        canvas.drawText("Day $day 🔥", 42f, 100f, bold)
        drawRec(canvas, width - 167f, 61f)

        bold.textSize = 37f
        bold.textAlign = Paint.Align.CENTER
        drawCenteredWrapped(canvas, topic, width / 2f, 200f, width - 100f, 44f, bold, 3)

        val elapsed = (timeUs / 1_000_000).toInt()
        val remaining = (duration - elapsed).coerceIn(0, duration)
        bold.textSize = 95f
        bold.typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.NORMAL)
        canvas.drawText("%02d:%02d".format(remaining / 60, remaining % 60), width / 2f, 467f, bold)

        val ratio = if (duration == 0) 0f else remaining.toFloat() / duration
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(222, 213, 232) }
        canvas.drawRoundRect(RectF(83f, 527f, width - 83f, 545f), 9f, 9f, track)
        val progress = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = when {
                ratio <= .15f -> Color.rgb(232, 60, 49)
                ratio <= .35f -> Color.rgb(243, 154, 50)
                else -> Color.rgb(85, 69, 133)
            }
        }
        canvas.drawRoundRect(RectF(83f, 527f, 83f + (width - 166f) * ratio, 545f), 9f, 9f, progress)
    }

    private fun drawRec(canvas: Canvas, x: Float, y: Float) {
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(232, 60, 49)
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }
        canvas.drawRoundRect(RectF(x, y, x + 123f, y + 57f), 29f, 29f, border)
        val red = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(232, 60, 49) }
        canvas.drawCircle(x + 25f, y + 29f, 10f, red)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(31, 29, 27)
            textSize = 30f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        canvas.drawText("REC", x + 45f, y + 39f, text)
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
        val size = 620f
        val cx = width / 2f + yaw * 28f
        val cy = half + 333f + pitch * 17f
        canvas.save()
        canvas.rotate(roll * 7f, cx, cy)
        canvas.translate(cx - size / 2f, cy - size / 2f)
        drawStateCat(canvas, size, leftEye, rightEye, mouth, smile, pitch)
        canvas.restore()
    }

    private fun drawStateCat(
        canvas: Canvas,
        unit: Float,
        leftEye: Float,
        rightEye: Float,
        mouth: Float,
        smile: Float,
        pitch: Float,
    ) {
        val coat = coatColor(avatarCat)
        val outline = if (avatarCat == "Black" || avatarCat == "Tuxedo") Color.rgb(10, 9, 9) else Color.rgb(35, 30, 27)
        val body = RectF(unit * .20f, unit * .31f, unit * .80f, unit * .76f)
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(26, 0, 0, 0)
            maskFilter = android.graphics.BlurMaskFilter(10f, android.graphics.BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawRoundRect(RectF(body).apply { offset(unit * .016f, unit * .020f) }, unit * .045f, unit * .045f, shadow)
        drawTail(canvas, unit, coat, outline)
        val fill = Paint().apply { color = coat }
        val leftEar = Path().apply {
            moveTo(unit * .23f, unit * .34f)
            lineTo(unit * .28f, unit * .17f)
            quadTo(unit * .33f, unit * .18f, unit * .38f, unit * .34f)
            close()
        }
        val rightEar = Path().apply {
            moveTo(unit * .62f, unit * .34f)
            quadTo(unit * .67f, unit * .18f, unit * .72f, unit * .17f)
            lineTo(unit * .77f, unit * .34f)
            close()
        }
        canvas.drawPath(leftEar, fill)
        canvas.drawPath(rightEar, fill)
        canvas.drawRoundRect(body, unit * .045f, unit * .045f, fill)
        drawCoatPatch(canvas, unit, coat)
        drawEarInner(canvas, unit)
        drawLegs(canvas, unit, coat, outline)
        val stroke = Paint().apply {
            color = outline
            style = Paint.Style.STROKE
            strokeWidth = unit * .014f
            strokeJoin = Paint.Join.ROUND
        }
        canvas.drawPath(leftEar, stroke)
        canvas.drawPath(rightEar, stroke)
        canvas.drawRoundRect(body, unit * .045f, unit * .045f, stroke)
        drawFace(canvas, unit, outline, leftEye, rightEye, mouth, smile, pitch)
        drawScarf(canvas, unit, outline)
    }

    private fun drawCoatPatch(canvas: Canvas, unit: Float, coat: Int) {
        val patch = Path().apply {
            moveTo(unit * .27f, unit * .31f)
            quadTo(unit * .37f, unit * .34f, unit * .43f, unit * .45f)
            quadTo(unit * .50f, unit * .58f, unit * .57f, unit * .45f)
            quadTo(unit * .63f, unit * .34f, unit * .73f, unit * .31f)
            lineTo(unit * .27f, unit * .31f)
            close()
        }
        when (avatarCat) {
            "Calico" -> {
                canvas.drawPath(patch, Paint().apply { color = Color.rgb(255, 248, 232) })
                canvas.drawPath(Path().apply {
                    moveTo(unit * .20f, unit * .31f)
                    lineTo(unit * .40f, unit * .31f)
                    quadTo(unit * .35f, unit * .47f, unit * .23f, unit * .53f)
                    lineTo(unit * .20f, unit * .53f)
                    close()
                }, Paint().apply { color = Color.rgb(231, 140, 37) })
                canvas.drawPath(Path().apply {
                    moveTo(unit * .60f, unit * .31f)
                    lineTo(unit * .80f, unit * .31f)
                    lineTo(unit * .80f, unit * .57f)
                    quadTo(unit * .68f, unit * .48f, unit * .60f, unit * .31f)
                    close()
                }, Paint().apply { color = Color.rgb(42, 39, 37) })
            }
            "Tuxedo" -> canvas.drawPath(Path().apply {
                moveTo(unit * .36f, unit * .31f)
                quadTo(unit * .43f, unit * .39f, unit * .50f, unit * .53f)
                quadTo(unit * .57f, unit * .39f, unit * .64f, unit * .31f)
                lineTo(unit * .64f, unit * .72f)
                lineTo(unit * .36f, unit * .72f)
                close()
            }, Paint().apply { color = Color.rgb(255, 250, 234) })
            "Black" -> Unit
            else -> canvas.drawPath(patch, Paint().apply { color = blend(coat, Color.BLACK, .16f, .55f) })
        }
    }

    private fun drawEarInner(canvas: Canvas, unit: Float) {
        val paint = Paint().apply { color = Color.rgb(255, 231, 223) }
        canvas.drawPath(Path().apply {
            moveTo(unit * .275f, unit * .31f)
            lineTo(unit * .30f, unit * .225f)
            lineTo(unit * .345f, unit * .31f)
            close()
        }, paint)
        canvas.drawPath(Path().apply {
            moveTo(unit * .655f, unit * .31f)
            lineTo(unit * .70f, unit * .225f)
            lineTo(unit * .725f, unit * .31f)
            close()
        }, paint)
    }

    private fun drawTail(canvas: Canvas, unit: Float, coat: Int, outline: Int) {
        val path = Path().apply {
            moveTo(unit * .79f, unit * .61f)
            cubicTo(unit * .93f, unit * .62f, unit * .92f, unit * .50f, unit * .90f, unit * .49f)
        }
        canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = outline
            style = Paint.Style.STROKE
            strokeWidth = unit * .065f
            strokeCap = Paint.Cap.ROUND
        })
        canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = coat
            style = Paint.Style.STROKE
            strokeWidth = unit * .045f
            strokeCap = Paint.Cap.ROUND
        })
    }

    private fun drawLegs(canvas: Canvas, unit: Float, coat: Int, outline: Int) {
        for (x in listOf(.30f, .70f)) {
            val foot = RectF(unit * x - unit * .035f, unit * .742f, unit * x + unit * .035f, unit * .787f)
            canvas.drawRoundRect(foot, unit * .014f, unit * .014f, Paint().apply { color = coat })
            canvas.drawRoundRect(foot, unit * .014f, unit * .014f, Paint().apply {
                color = outline
                style = Paint.Style.STROKE
                strokeWidth = unit * .012f
            })
        }
    }

    private fun drawFace(
        canvas: Canvas,
        unit: Float,
        outline: Int,
        leftEye: Float,
        rightEye: Float,
        mouth: Float,
        smile: Float,
        pitch: Float,
    ) {
        val blink = max(1f - leftEye, 1f - rightEye).coerceIn(0f, 1f)
        val tired = pitch > .32f
        val eyeColor = when (avatarCat) {
            "Black" -> Color.rgb(255, 227, 110)
            "Tuxedo" -> Color.rgb(16, 16, 16)
            else -> Color.rgb(23, 23, 23)
        }
        drawEye(canvas, unit, unit * .39f, unit * .485f, blink, tired, eyeColor)
        drawEye(canvas, unit, unit * .61f, unit * .485f, blink, tired, eyeColor)
        val faceLine = if (avatarCat == "Black") Color.rgb(255, 243, 209) else outline
        val line = Paint().apply {
            color = faceLine
            strokeWidth = unit * .014f
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawLine(unit * .30f, unit * .53f, unit * .24f, unit * .525f, line)
        canvas.drawLine(unit * .30f, unit * .56f, unit * .24f, unit * .565f, line)
        canvas.drawLine(unit * .70f, unit * .53f, unit * .76f, unit * .525f, line)
        canvas.drawLine(unit * .70f, unit * .56f, unit * .76f, unit * .565f, line)
        canvas.drawCircle(unit * .50f, unit * .555f, unit * .010f, Paint().apply { color = faceLine })
        drawMouth(canvas, unit, faceLine, mouth, smile)
    }

    private fun drawEye(canvas: Canvas, unit: Float, x: Float, y: Float, blink: Float, tired: Boolean, eyeColor: Int) {
        if (blink > .72f || tired) {
            canvas.drawLine(x - unit * .030f, y, x + unit * .030f, y - if (tired) unit * .008f else 0f, Paint().apply {
                color = eyeColor
                strokeWidth = unit * .014f
                strokeCap = Paint.Cap.ROUND
            })
            return
        }
        val h = unit * .080f * (1f - blink * .55f)
        val rect = RectF(x - unit * .0215f, y - h / 2f, x + unit * .0215f, y + h / 2f)
        canvas.drawRoundRect(rect, unit * .010f, unit * .010f, Paint().apply { color = eyeColor })
        canvas.drawCircle(x - unit * .007f, rect.top + unit * .017f, unit * .006f, Paint().apply { color = Color.WHITE })
    }

    private fun drawMouth(canvas: Canvas, unit: Float, outline: Int, mouth: Float, smile: Float) {
        if (smile > .72f && mouth < .32f) {
            canvas.drawArc(RectF(unit * .455f, unit * .530f, unit * .545f, unit * .600f), 0f, 180f, false, Paint().apply {
                color = outline
                style = Paint.Style.STROKE
                strokeWidth = unit * .012f
                strokeCap = Paint.Cap.ROUND
            })
            return
        }
        if (mouth < .18f) {
            val path = Path().apply {
                moveTo(unit * .475f, unit * .575f)
                quadTo(unit * .50f, unit * .588f, unit * .525f, unit * .575f)
            }
            canvas.drawPath(path, Paint().apply {
                color = outline
                style = Paint.Style.STROKE
                strokeWidth = unit * .010f
                strokeCap = Paint.Cap.ROUND
            })
            return
        }
        val scale = if (mouth < .38f) Pair(.055f, .052f) else if (mouth < .68f) Pair(.095f, .090f) else Pair(.135f, .145f)
        val rect = RectF(unit * .50f - unit * scale.first / 2f, unit * .585f - unit * scale.second / 2f, unit * .50f + unit * scale.first / 2f, unit * .585f + unit * scale.second / 2f)
        canvas.drawRoundRect(rect, unit * .008f, unit * .008f, Paint().apply { color = outline })
        rect.inset(unit * .008f, unit * .008f)
        canvas.drawRoundRect(rect, unit * .006f, unit * .006f, Paint().apply { color = Color.rgb(240, 154, 156) })
    }

    private fun drawScarf(canvas: Canvas, unit: Float, outline: Int) {
        val neck = RectF(unit * .28f, unit * .735f, unit * .72f, unit * .795f)
        canvas.drawRoundRect(neck, unit * .014f, unit * .014f, Paint().apply { color = scarfColor })
        val tail = Path().apply {
            moveTo(unit * .49f, unit * .785f)
            lineTo(unit * .59f, unit * .895f)
            quadTo(unit * .54f, unit * .915f, unit * .47f, unit * .795f)
            close()
        }
        canvas.drawPath(tail, Paint().apply { color = blend(scarfColor, Color.BLACK, .12f) })
        canvas.drawRoundRect(neck, unit * .014f, unit * .014f, Paint().apply {
            color = outline
            style = Paint.Style.STROKE
            strokeWidth = unit * .010f
        })
        canvas.drawLine(unit * .32f, unit * .765f, unit * .68f, unit * .765f, Paint().apply {
            color = Color.argb(72, 255, 255, 255)
            strokeWidth = unit * .010f
            strokeCap = Paint.Cap.ROUND
        })
    }

    private fun coatColor(name: String) = when (name) {
        "Ginger" -> Color.rgb(231, 140, 37)
        "Gray" -> Color.rgb(146, 144, 143)
        "Black" -> Color.rgb(28, 27, 30)
        "Siamese" -> Color.rgb(118, 81, 60)
        "Tuxedo" -> Color.rgb(24, 24, 26)
        "Calico" -> Color.rgb(240, 227, 205)
        "Brown Tabby" -> Color.rgb(168, 109, 49)
        else -> Color.rgb(244, 235, 217)
    }

    private fun sampleAt(timeMs: Long): Map<*, *>? {
        if (samples.isEmpty()) return null
        val index = (timeMs / 66).toInt().coerceIn(0, samples.lastIndex)
        return samples[index]
    }

    private fun number(sample: Map<*, *>?, key: String, fallback: Float = 0f): Float =
        (sample?.get(key) as? Number)?.toFloat() ?: fallback

    private fun drawTranscript(canvas: Canvas, timeUs: Long) {
        if (transcriptSegments.isEmpty()) return
        val timeMs = timeUs / 1000L
        val active = transcriptSegments.firstOrNull {
            val start = ((it["startMs"] as? Number)?.toLong() ?: 0L) - 350L
            val end = ((it["endMs"] as? Number)?.toLong() ?: start + 3000L) + 900L
            timeMs in start..end
        } ?: transcriptSegments.lastOrNull {
            val start = (it["startMs"] as? Number)?.toLong() ?: 0L
            val end = ((it["endMs"] as? Number)?.toLong() ?: start + 3000L) + 1400L
            timeMs >= start && timeMs <= end
        } ?: return
        val text = (active["text"] as? String)?.trim().orEmpty()
        if (text.isEmpty()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 30f
            textAlign = Paint.Align.CENTER
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }
        val lines = wrapLines(text, paint, width - 110f, 2)
        val lineHeight = 38f
        val boxHeight = 34f + lines.size * lineHeight
        val top = height - 92f - boxHeight
        val box = RectF(52f, top, width - 52f, top + boxHeight)
        canvas.drawRoundRect(box, 20f, 20f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(178, 18, 17, 16) })
        lines.forEachIndexed { index, line ->
            canvas.drawText(line, width / 2f, top + 45f + index * lineHeight, paint)
        }
    }

    private fun wrapLines(value: String, paint: Paint, maxWidth: Float, maxLines: Int): List<String> {
        val words = value.split(Regex("\\s+")).filter { it.isNotBlank() }
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
        return lines
    }

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

    private fun blend(from: Int, to: Int, amount: Float, alpha: Float = 1f): Int {
        val inverse = 1f - amount
        return Color.argb(
            (255 * alpha).roundToInt().coerceIn(0, 255),
            (Color.red(from) * inverse + Color.red(to) * amount).roundToInt(),
            (Color.green(from) * inverse + Color.green(to) * amount).roundToInt(),
            (Color.blue(from) * inverse + Color.blue(to) * amount).roundToInt(),
        )
    }

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
