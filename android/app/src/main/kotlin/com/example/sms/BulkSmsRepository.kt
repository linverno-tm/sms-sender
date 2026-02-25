package com.example.sms

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

data class QueueItem(
    val id: Long,
    val number: String,
    val position: Int,
)

data class BulkStatus(
    val state: String,
    val total: Int,
    val sent: Int,
    val failed: Int,
    val currentIndex: Int,
    val currentNumber: String?,
    val message: String?,
) {
    val pending: Int
        get() = (total - sent - failed).coerceAtLeast(0)

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "state" to state,
            "total" to total,
            "sent" to sent,
            "failed" to failed,
            "pending" to pending,
            "currentIndex" to currentIndex,
            "currentNumber" to currentNumber,
            "message" to message,
        )
    }
}

class BulkSmsDbHelper(context: Context) :
    SQLiteOpenHelper(context, "bulk_sms.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE campaign (
              id INTEGER PRIMARY KEY,
              message TEXT NOT NULL,
              state TEXT NOT NULL,
              total INTEGER NOT NULL,
              sent INTEGER NOT NULL,
              failed INTEGER NOT NULL,
              current_index INTEGER NOT NULL,
              current_number TEXT,
              updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )

        db.execSQL(
            """
            CREATE TABLE queue (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              campaign_id INTEGER NOT NULL,
              number TEXT NOT NULL,
              status TEXT NOT NULL,
              position INTEGER NOT NULL,
              error TEXT
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS queue")
        db.execSQL("DROP TABLE IF EXISTS campaign")
        onCreate(db)
    }
}

class BulkSmsRepository(context: Context) {
    private val helper = BulkSmsDbHelper(context.applicationContext)

    @Synchronized
    fun createNewCampaign(numbers: List<String>, message: String) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            db.delete("queue", null, null)
            db.delete("campaign", null, null)

            val now = System.currentTimeMillis()
            val campaignValues = ContentValues().apply {
                put("id", 1)
                put("message", message)
                put("state", "sending")
                put("total", numbers.size)
                put("sent", 0)
                put("failed", 0)
                put("current_index", 0)
                put("current_number", "")
                put("updated_at", now)
            }
            db.insertOrThrow("campaign", null, campaignValues)

            numbers.forEachIndexed { index, number ->
                val values = ContentValues().apply {
                    put("campaign_id", 1)
                    put("number", number)
                    put("status", "pending")
                    put("position", index)
                }
                db.insertOrThrow("queue", null, values)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun markSending(position: Int, number: String) {
        val values = ContentValues().apply {
            put("state", "sending")
            put("current_index", position)
            put("current_number", number)
            put("updated_at", System.currentTimeMillis())
        }
        helper.writableDatabase.update("campaign", values, "id = 1", null)
    }

    @Synchronized
    fun markSent(queueId: Long, position: Int, number: String) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val queueValues = ContentValues().apply {
                put("status", "sent")
                put("error", "")
            }
            db.update("queue", queueValues, "id = ?", arrayOf(queueId.toString()))

            db.execSQL("UPDATE campaign SET sent = sent + 1 WHERE id = 1")
            markSending(position, number)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun markFailed(queueId: Long, position: Int, number: String, error: String) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            val queueValues = ContentValues().apply {
                put("status", "failed")
                put("error", error)
            }
            db.update("queue", queueValues, "id = ?", arrayOf(queueId.toString()))

            db.execSQL("UPDATE campaign SET failed = failed + 1 WHERE id = 1")
            markSending(position, number)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun nextPending(): QueueItem? {
        val cursor = helper.readableDatabase.rawQuery(
            "SELECT id, number, position FROM queue WHERE status = 'pending' ORDER BY position ASC LIMIT 1",
            null,
        )
        cursor.use {
            if (!it.moveToFirst()) {
                return null
            }
            return QueueItem(
                id = it.getLong(0),
                number = it.getString(1),
                position = it.getInt(2),
            )
        }
    }

    @Synchronized
    fun setState(state: String) {
        val values = ContentValues().apply {
            put("state", state)
            put("updated_at", System.currentTimeMillis())
        }
        helper.writableDatabase.update("campaign", values, "id = 1", null)
    }

    @Synchronized
    fun getStatus(): BulkStatus {
        val cursor = helper.readableDatabase.rawQuery(
            "SELECT state, total, sent, failed, current_index, current_number, message FROM campaign WHERE id = 1 LIMIT 1",
            null,
        )
        cursor.use {
            if (!it.moveToFirst()) {
                return BulkStatus(
                    state = "idle",
                    total = 0,
                    sent = 0,
                    failed = 0,
                    currentIndex = 0,
                    currentNumber = null,
                    message = null,
                )
            }
            return BulkStatus(
                state = it.getString(0),
                total = it.getInt(1),
                sent = it.getInt(2),
                failed = it.getInt(3),
                currentIndex = it.getInt(4),
                currentNumber = it.getString(5),
                message = it.getString(6),
            )
        }
    }

    @Synchronized
    fun hasUnfinishedCampaign(): Boolean {
        val status = getStatus()
        return status.total > 0 && status.pending > 0 && (status.state == "sending" || status.state == "stopped")
    }
}
