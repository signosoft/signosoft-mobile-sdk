package com.signosoft.signer

import java.io.File
import kotlin.io.encoding.Base64

/**
 * Writes the signed PDF that the shell ships as base64 into a file the host app
 * can read.
 *
 * The bytes cross the JS→native bridge inside a single `@JavascriptInterface`
 * argument. The ceiling below is ours, and it is about peak memory: the base64
 * string, the decoded bytes and the write buffer are all resident at once.
 *
 * Every failure yields null rather than throwing: the signature is already
 * recorded server-side by the time this runs, so a missing local copy must
 * never turn a completed signature into an error. The host still gets `signed`,
 * with a null path, and fetches the document by `documentToken`.
 */
internal class SignedPdfStore(
    private val directory: File,
    private val maximumBytes: Int = DEFAULT_MAXIMUM_BYTES,
) {
    fun write(base64: String?, fileName: String?): File? {
        if (base64.isNullOrEmpty()) return null
        // Four base64 characters carry three bytes; check before allocating.
        if (base64.length / 4 * 3 > maximumBytes) return null

        val bytes = runCatching { Base64.decode(base64) }.getOrNull() ?: return null
        if (bytes.isEmpty() || bytes.size > maximumBytes) return null

        val file = File(directory, safeName(fileName))
        return runCatching {
            file.writeBytes(bytes)
            file
        }.getOrNull()
    }

    companion object {
        /**
         * Decoded-bytes ceiling. Documents at or below this arrive as a local
         * file; above it the signature still succeeds and the path is null.
         */
        const val DEFAULT_MAXIMUM_BYTES = 32 * 1024 * 1024

        /**
         * The shell supplies the document's own name, so it is never trusted as
         * a path: only the last component survives, and it may not walk upwards.
         */
        fun safeName(fileName: String?): String {
            val fallback = "document.pdf"
            val last = fileName?.split("/")?.lastOrNull { it.isNotEmpty() } ?: return fallback
            return if (last == "." || last == "..") fallback else last
        }
    }
}
