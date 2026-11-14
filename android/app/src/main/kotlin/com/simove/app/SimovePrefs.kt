package com.simove.app

import android.content.Context
import android.content.SharedPreferences

object SimovePrefs {
    private const val NAME = "simove_native"
    private const val TARGET_PACKAGE = "target_package"
    private const val OVERLAY_TODAY = "overlay_today"
    private const val OVERLAY_LATEST = "overlay_latest"
    private const val OVERLAY_STATUS = "overlay_status"
    private const val OVERLAY_REFERENCE = "overlay_reference"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun targetPackage(context: Context): String =
        prefs(context).getString(TARGET_PACKAGE, "com.angkas.rider")
            ?: "com.angkas.rider"

    fun setTargetPackage(context: Context, value: String) {
        prefs(context).edit().putString(TARGET_PACKAGE, value.trim()).apply()
    }

    fun overlayValues(context: Context): Map<String, String> {
        val p = prefs(context)
        return mapOf(
            "today" to (p.getString(OVERLAY_TODAY, "₱0.00") ?: "₱0.00"),
            "latest" to (p.getString(OVERLAY_LATEST, "—") ?: "—"),
            "status" to (p.getString(OVERLAY_STATUS, "Monitoring off") ?: "Monitoring off"),
            "reference" to (p.getString(OVERLAY_REFERENCE, "") ?: ""),
        )
    }

    fun saveOverlayValues(context: Context, values: Map<String, String>) {
        prefs(context).edit()
            .putString(OVERLAY_TODAY, values["today"])
            .putString(OVERLAY_LATEST, values["latest"])
            .putString(OVERLAY_STATUS, values["status"])
            .putString(OVERLAY_REFERENCE, values["reference"])
            .apply()
    }
}
