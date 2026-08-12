package com.speakup.app.speak_up

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer

class AudioExtractor(private val context: Context) {
    fun extractWav(videoPath: String): String {
        val extractor = MediaExtractor()
        extractor.setDataSource(videoPath)
        val track = (0 until extractor.trackCount).firstOrNull { index ->
            extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: run {
            extractor.release()
            error("The recording did not contain an audio track")
        }
        val format = extractor.getTrackFormat(track)
        val mime = format.getString(MediaFormat.KEY_MIME) ?: error("Audio format is missing")
        extractor.selectTrack(track)
        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(format, null, null, 0)
        decoder.start()

        val pcm = ArrayList<ByteArray>()
        var totalBytes = 0
        var inputDone = false
        var outputDone = false
        var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val info = MediaCodec.BufferInfo()
        while (!outputDone) {
            if (!inputDone) {
                val inputIndex = decoder.dequeueInputBuffer(10_000)
                if (inputIndex >= 0) {
                    val buffer = decoder.getInputBuffer(inputIndex)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(
                            inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        inputDone = true
                    } else {
                        decoder.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val outputIndex = decoder.dequeueOutputBuffer(info, 10_000)
            if (outputIndex >= 0) {
                if (info.size > 0) {
                    val buffer = decoder.getOutputBuffer(outputIndex)!!
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val bytes = ByteArray(info.size)
                    buffer.get(bytes)
                    pcm.add(bytes)
                    totalBytes += bytes.size
                }
                outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                decoder.releaseOutputBuffer(outputIndex, false)
            } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val outputFormat = decoder.outputFormat
                sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            }
        }
        decoder.stop()
        decoder.release()
        extractor.release()

        val raw = ByteArray(totalBytes)
        var offset = 0
        pcm.forEach { part ->
            part.copyInto(raw, offset)
            offset += part.size
        }
        val mono16k = resampleToMono16k(raw, sampleRate, channels)
        val output = File(context.cacheDir, "speakup-audio-${System.currentTimeMillis()}.wav")
        writeWav(output, mono16k, 16_000, 1)
        return output.absolutePath
    }

    private fun resampleToMono16k(input: ByteArray, sampleRate: Int, channels: Int): ByteArray {
        val frameCount = input.size / 2 / channels
        if (frameCount <= 0) error("The audio track was empty")
        val outputFrames = (frameCount.toLong() * 16_000L / sampleRate).toInt().coerceAtLeast(1)
        val output = ByteArray(outputFrames * 2)
        for (outIndex in 0 until outputFrames) {
            val sourcePosition = outIndex.toDouble() * sampleRate / 16_000.0
            val sourceIndex = sourcePosition.toInt().coerceIn(0, frameCount - 1)
            var sum = 0
            for (channel in 0 until channels) {
                val byteIndex = (sourceIndex * channels + channel) * 2
                val sample = (input[byteIndex].toInt() and 0xff) or (input[byteIndex + 1].toInt() shl 8)
                sum += sample.toShort().toInt()
            }
            val sample = (sum / channels).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output[outIndex * 2] = (sample and 0xff).toByte()
            output[outIndex * 2 + 1] = ((sample shr 8) and 0xff).toByte()
        }
        return output
    }

    private fun writeWav(file: File, audio: ByteArray, sampleRate: Int, channels: Int) {
        RandomAccessFile(file, "rw").use { out ->
            out.setLength(0)
            out.writeBytes("RIFF")
            writeLeInt(out, 36 + audio.size)
            out.writeBytes("WAVEfmt ")
            writeLeInt(out, 16)
            writeLeShort(out, 1)
            writeLeShort(out, channels)
            writeLeInt(out, sampleRate)
            writeLeInt(out, sampleRate * channels * 2)
            writeLeShort(out, channels * 2)
            writeLeShort(out, 16)
            out.writeBytes("data")
            writeLeInt(out, audio.size)
            out.write(audio)
        }
    }

    private fun writeLeInt(out: RandomAccessFile, value: Int) {
        out.write(byteArrayOf(value.toByte(), (value shr 8).toByte(), (value shr 16).toByte(), (value shr 24).toByte()))
    }

    private fun writeLeShort(out: RandomAccessFile, value: Int) {
        out.write(byteArrayOf(value.toByte(), (value shr 8).toByte()))
    }
}
