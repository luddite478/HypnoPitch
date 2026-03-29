package com.hypnopitch.app

import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val padChannelName = "hypnopitch/pad"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, padChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAssetPackPath" -> {
                        val packName = call.argument<String>("packName")
                        if (packName.isNullOrBlank()) {
                            result.error("invalid_args", "packName is required", null)
                            return@setMethodCallHandler
                        }

                        val manager = AssetPackManagerFactory.getInstance(applicationContext)
                        val location = manager.getPackLocation(packName)
                        val assetsPath = location?.assetsPath()
                        result.success(assetsPath)
                    }
                    "readAssetBytes" -> {
                        val packName = call.argument<String>("packName")
                        val assetPath = call.argument<String>("assetPath")
                        if (packName.isNullOrBlank() || assetPath.isNullOrBlank()) {
                            result.error(
                                "invalid_args",
                                "packName and assetPath are required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        try {
                            val bytes = readAssetBytes(packName, assetPath)
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("read_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun readAssetBytes(packName: String, assetPath: String): ByteArray? {
        val manager = AssetPackManagerFactory.getInstance(applicationContext)
        val location = manager.getPackLocation(packName)
        val candidates = mutableListOf<String>()
        candidates.add(assetPath)
        if (assetPath.startsWith("samples/")) {
            candidates.add(assetPath.removePrefix("samples/"))
        }

        // First: try direct file read from extracted asset pack location.
        val assetsRoot = location?.assetsPath()
        if (!assetsRoot.isNullOrBlank()) {
            for (candidate in candidates) {
                val file = File(assetsRoot, candidate)
                if (file.exists() && file.isFile) {
                    return file.readBytes()
                }
            }
        }

        // Fallback: try Android AssetManager. This can work for installed split APK assets.
        for (candidate in candidates) {
            try {
                assets.open(candidate).use { input ->
                    return input.readBytes()
                }
            } catch (_: Exception) {
                // Try next candidate.
            }
        }
        return null
    }
}
