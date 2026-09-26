package com.quizsync.android.core.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/** 同步实体（`entity` 取值，协议冻结）。 */
object SyncEntity {
    const val SESSION = "session"
    const val QUESTION = "question"
    const val COLLECTION = "collection"
    const val SESSION_IMAGE = "session_image"
    const val IMAGE = "image"
    const val DEVICE = "device"
    const val SNAPSHOT = "snapshot"
}

/** op 类型。 */
object SyncOpType {
    const val UPSERT = "upsert"
    const val DELETE = "delete"
}

/**
 * 一条同步 op（`spec/06-sync.md`）。
 *
 * `fields` 里的键是**数据库列名**，值是该列的目标值 —— 字段级 LWW 就是按这些键逐列比较的。
 */
@kotlinx.serialization.Serializable
data class SyncOp(
    val op_id: String,
    val device_id: String,
    val lamport: Long,
    val entity: String,
    val entity_id: String,
    val op_type: String,
    val fields_json: Map<String, JsonElement> = emptyMap(),
    val created_at: Long = 0,
) {
    companion object {
        fun parse(element: JsonElement): SyncOp = Json.decodeFromJsonElement(serializer(), element)

        /** 线上 `fields_json` 是**对象**（库里那一列是 TEXT，别搞混）。 */
        fun fieldsOf(element: JsonElement): Map<String, JsonElement> =
            element.jsonObject["fields_json"]?.jsonObject ?: emptyMap()
    }
}

/** 字段时钟：`{字段: {"l": lamport, "d": deviceId}}`。 */
data class FieldClock(val lamport: Long, val device: String) {
    /**
     * 逐字段 LWW 的比较键是 **(lamport, device_id)** 的字典序；
     * **相等即判负**（不覆盖）—— 同一台设备用同一个 lamport 再写一次是平局。
     */
    fun losesTo(candidate: SyncOp): Boolean {
        val byLamport = candidate.lamport.compareTo(lamport)
        if (byLamport != 0) return byLamport <= 0
        return candidate.device_id <= device
    }
}

/** 把 `field_clocks_json` 读成 map。 */
fun parseFieldClocks(raw: String?): MutableMap<String, FieldClock> {
    if (raw.isNullOrBlank()) return mutableMapOf()
    val clocks = mutableMapOf<String, FieldClock>()
    val obj = runCatching { Json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return clocks
    for ((field, value) in obj) {
        val clock = value.jsonObject
        clocks[field] = FieldClock(
            lamport = (clock["l"] as? JsonPrimitive)?.content?.toLongOrNull() ?: 0L,
            device = (clock["d"] as? JsonPrimitive)?.content.orEmpty(),
        )
    }
    return clocks
}

/** 把字段时钟写成 `field_clocks_json`。 */
fun encodeFieldClocks(clocks: Map<String, FieldClock>): String {
    val obj = JsonObject(
        clocks.mapValues { (_, clock) ->
            JsonObject(
                mapOf(
                    "l" to JsonPrimitive(clock.lamport),
                    "d" to JsonPrimitive(clock.device),
                ),
            )
        },
    )
    return obj.toString()
}

/** 字段值 → 绑定参数（SQLite 只认 String/Long/Double/ByteArray/null）。 */
fun bindValue(value: JsonElement?): Any? = when (value) {
    null -> null
    is JsonPrimitive -> when {
        value.isString -> value.content
        value.content == "true" -> 1L
        value.content == "false" -> 0L
        value.content.toLongOrNull() != null -> value.content.toLong()
        value.content.toDoubleOrNull() != null -> value.content.toDouble()
        else -> value.content
    }
    else -> value.toString()
}
