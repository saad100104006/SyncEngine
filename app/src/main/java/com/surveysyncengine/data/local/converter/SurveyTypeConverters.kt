package com.surveysyncengine.data.local.converter

import androidx.room.TypeConverter
import com.surveysyncengine.domain.model.AnswerValue
import com.surveysyncengine.domain.model.GpsPoint
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.model.UploadStatus
import org.json.JSONArray
import org.json.JSONObject

/**
 * Room TypeConverters for all non-primitive types used in survey entities.
 *
 * Registered at the database level via [@TypeConverters(SurveyTypeConverters::class)].
 * Room calls the [@TypeConverter]-annotated functions automatically when reading
 * from or writing to SQLite — no manual invocation needed.
 *
 * Uses [org.json] (bundled with Android) to avoid an external JSON dependency.
 * Moshi or Gson are drop-in alternatives
 *
 * JSON schema for [AnswerValue]:
 * ```json
 * { "type": "TEXT" | "NUMBER" | "BOOL" | "GPS" | "GPS_BOUNDARY" | "MULTI" | "SKIPPED",
 *   ...type-specific payload fields }
 * ```
 */
class SurveyTypeConverters {

    // ------------------------------------------------------------------
    // SyncStatus
    // ------------------------------------------------------------------

    /**
     * Writes [SyncStatus] to SQLite as its enum name string (e.g. `"PENDING"`).
     * Storing as a string rather than an ordinal means the column remains readable
     * in raw SQL queries and survives enum reordering without corrupting existing rows.
     */
    @TypeConverter
    fun syncStatusToString(v: SyncStatus): String = v.name

    /**
     * Reads a [SyncStatus] from its stored string name.
     *
     * @throws IllegalArgumentException if the stored value does not match any
     *   [SyncStatus] constant — indicates a schema/code mismatch after a rename.
     */
    @TypeConverter
    fun stringToSyncStatus(v: String): SyncStatus = SyncStatus.valueOf(v)

    // ------------------------------------------------------------------
    // UploadStatus
    // ------------------------------------------------------------------

    /**
     * Writes [UploadStatus] to SQLite as its enum name string (e.g. `"PENDING"`).
     * Same rationale as [syncStatusToString] — readable and rename-safe.
     */
    @TypeConverter
    fun uploadStatusToString(v: UploadStatus): String = v.name

    /**
     * Reads an [UploadStatus] from its stored string name.
     *
     * @throws IllegalArgumentException if the stored value does not match any
     *   [UploadStatus] constant.
     */
    @TypeConverter
    fun stringToUploadStatus(v: String): UploadStatus = UploadStatus.valueOf(v)

    // ------------------------------------------------------------------
    // Map<String, AnswerValue>
    // ------------------------------------------------------------------

    /**
     * Serialises the entire answers map for one [ResponseSection] to a JSON string
     * for storage in a single SQLite TEXT column.
     *
     * Each entry becomes `"questionKey": { "type": "...", ...payload }`.
     * The outer structure (which question keys exist) is relational — only the
     * values inside each answer are JSON-encoded here.
     *
     * @param answers map of question key → typed answer value; may be empty.
     * @return a non-null JSON string, at minimum `"{}"` for an empty map.
     */
    @TypeConverter
    fun answersToJson(answers: Map<String, AnswerValue>): String {
        val json = JSONObject()
        answers.forEach { (key, value) -> json.put(key, answerToJson(value)) }
        return json.toString()
    }

    /**
     * Deserialises a JSON string back into a [Map] of question key → [AnswerValue].
     *
     * Unknown `"type"` values fall back to [AnswerValue.Skipped] rather than
     * throwing, so a future server-introduced answer type does not crash older
     * app versions reading existing rows.
     *
     * @param json the stored JSON string produced by [answersToJson].
     * @return a map preserving the original question keys; empty map for `"{}"`.
     */
    @TypeConverter
    fun jsonToAnswers(json: String): Map<String, AnswerValue> {
        val obj = JSONObject(json)
        return obj.keys().asSequence().associateWith { key ->
            jsonToAnswer(obj.getJSONObject(key))
        }
    }

    // ------------------------------------------------------------------
    // Private helpers — AnswerValue ↔ JSONObject
    // ------------------------------------------------------------------

    /**
     * Converts a single [AnswerValue] to its JSON representation.
     *
     * Every variant writes a `"type"` discriminator field so [jsonToAnswer] can
     * reconstruct the correct sealed subclass without additional metadata.
     * Type-specific payload fields vary per variant:
     * - [AnswerValue.Text]          → `"value": String`
     * - [AnswerValue.Number]        → `"value": Double`
     * - [AnswerValue.Bool]          → `"value": Boolean`
     * - [AnswerValue.GpsCoordinate] → `"point": { lat, lng, accuracy }`
     * - [AnswerValue.GpsBoundary]   → `"vertices": [ { lat, lng, accuracy }, … ]`
     * - [AnswerValue.MultiChoice]   → `"value": [ String, … ]`
     * - [AnswerValue.Skipped]       → no payload beyond the type discriminator
     */
    private fun answerToJson(answer: AnswerValue): JSONObject = JSONObject().apply {
        when (answer) {
            is AnswerValue.Text   -> { put("type", "TEXT");   put("value", answer.value) }
            is AnswerValue.Number -> { put("type", "NUMBER"); put("value", answer.value) }
            is AnswerValue.Bool   -> { put("type", "BOOL");   put("value", answer.value) }

            is AnswerValue.GpsCoordinate -> {
                put("type", "GPS")
                put("point", gpsPointToJson(answer.point))
            }

            is AnswerValue.GpsBoundary -> {
                // Vertices are stored in capture order — winding direction matters
                // for server-side polygon area and self-intersection calculations.
                put("type", "GPS_BOUNDARY")
                put("vertices", JSONArray().apply {
                    answer.vertices.forEach { put(gpsPointToJson(it)) }
                })
            }

            is AnswerValue.MultiChoice -> {
                put("type", "MULTI")
                put("value", JSONArray(answer.selected))
            }

            is AnswerValue.Skipped -> put("type", "SKIPPED")
        }
    }

    /**
     * Reconstructs an [AnswerValue] from its JSON object representation.
     *
     * Dispatches on the `"type"` discriminator written by [answerToJson].
     * Any unrecognised type string returns [AnswerValue.Skipped] rather than
     * throwing — this makes the converter forward-compatible with new answer
     * types introduced by future server-side survey schema changes.
     *
     * @param obj a JSON object containing at minimum a `"type"` field.
     */
    private fun jsonToAnswer(obj: JSONObject): AnswerValue = when (obj.getString("type")) {
        "TEXT"    -> AnswerValue.Text(obj.getString("value"))
        "NUMBER"  -> AnswerValue.Number(obj.getDouble("value"))
        "BOOL"    -> AnswerValue.Bool(obj.getBoolean("value"))

        "GPS" -> AnswerValue.GpsCoordinate(
            point = jsonToGpsPoint(obj.getJSONObject("point")),
        )

        "GPS_BOUNDARY" -> {
            val arr = obj.getJSONArray("vertices")
            AnswerValue.GpsBoundary(
                vertices = (0 until arr.length()).map { jsonToGpsPoint(arr.getJSONObject(it)) }
            )
        }

        "MULTI" -> {
            val arr = obj.getJSONArray("value")
            AnswerValue.MultiChoice((0 until arr.length()).map { arr.getString(it) })
        }

        // SKIPPED or any future unknown type → treat as skipped rather than crash.
        // This keeps older app versions readable after new answer types are deployed.
        else -> AnswerValue.Skipped
    }

    // ------------------------------------------------------------------
    // Private helpers — GpsPoint ↔ JSONObject
    // ------------------------------------------------------------------

    /**
     * Serialises a [GpsPoint] to a JSON object.
     *
     * Extracted as a shared helper because the same format is used by both
     * [AnswerValue.GpsCoordinate] (single point) and [AnswerValue.GpsBoundary]
     * (array of points), ensuring the on-disk format is identical in both cases.
     *
     * Stored fields: `lat` (Double), `lng` (Double), `accuracy` (Float as Double).
     */
    private fun gpsPointToJson(point: GpsPoint): JSONObject = JSONObject().apply {
        put("lat", point.lat)
        put("lng", point.lng)
        put("accuracy", point.accuracyMeters)
    }

    /**
     * Deserialises a [GpsPoint] from a JSON object produced by [gpsPointToJson].
     *
     * `accuracy` is stored as a JSON Double (JSON has no float type) and cast
     * back to [Float] on read. Precision loss is negligible — GPS accuracy values
     * are typically in the range 1–100 m, well within Float's 7-digit precision.
     *
     * @param obj a JSON object containing `lat`, `lng`, and `accuracy` fields.
     */
    private fun jsonToGpsPoint(obj: JSONObject): GpsPoint = GpsPoint(
        lat = obj.getDouble("lat"),
        lng = obj.getDouble("lng"),
        accuracyMeters = obj.getDouble("accuracy").toFloat(),
    )
}
