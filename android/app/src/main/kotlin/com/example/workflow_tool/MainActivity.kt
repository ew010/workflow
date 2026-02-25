package com.example.workflow_tool

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "workflow_tool/atomics"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    result.success(handleCall(call))
                } catch (e: IllegalArgumentException) {
                    result.error("INVALID_ARGUMENT", e.message, null)
                } catch (e: SecurityException) {
                    result.error("SECURITY", e.message, null)
                } catch (e: Exception) {
                    result.error("EXECUTION_FAILED", e.message, null)
                }
            }
    }

    private fun handleCall(call: MethodCall): Any {
        return when (call.method) {
            "deleteFolder" -> {
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("path 不能为空")
                deleteFolder(path)
            }

            "copyFolder" -> {
                val sourcePath = call.argument<String>("sourcePath")
                    ?: throw IllegalArgumentException("sourcePath 不能为空")
                val targetPath = call.argument<String>("targetPath")
                    ?: throw IllegalArgumentException("targetPath 不能为空")
                copyFolder(sourcePath, targetPath)
            }

            "setSystemTimeManual" -> {
                val epochMillis = call.argument<Number>("epochMillis")?.toLong()
                    ?: throw IllegalArgumentException("epochMillis 不能为空")
                setSystemTimeManual(epochMillis)
            }

            "setSystemTimeAuto" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                setSystemTimeAuto(enabled)
            }

            "openApp" -> {
                val packageName = call.argument<String>("packageName")
                    ?: throw IllegalArgumentException("packageName 不能为空")
                openApp(packageName)
            }
            "searchApps" -> {
                val query = call.argument<String>("query") ?: ""
                searchApps(query)
            }

            else -> throw IllegalArgumentException("不支持的方法: ${call.method}")
        }
    }

    private fun deleteFolder(path: String): String {
        val target = File(path)
        if (!target.exists()) {
            return "文件夹不存在，已跳过: $path"
        }
        if (!target.isDirectory) {
            throw IllegalArgumentException("目标不是文件夹: $path")
        }
        if (!target.deleteRecursively() && target.exists()) {
            throw IOException("删除失败: $path")
        }
        return "删除成功: $path"
    }

    private fun copyFolder(sourcePath: String, targetPath: String): String {
        val source = File(sourcePath)
        if (!source.exists() || !source.isDirectory) {
            throw IllegalArgumentException("源文件夹不存在: $sourcePath")
        }

        val target = File(targetPath)
        copyDirectory(source, target)
        return "复制成功: $sourcePath -> $targetPath"
    }

    private fun copyDirectory(source: File, target: File) {
        if (source.isDirectory) {
            if (!target.exists() && !target.mkdirs()) {
                throw IOException("无法创建目录: ${target.absolutePath}")
            }

            source.listFiles()?.forEach { child ->
                copyDirectory(child, File(target, child.name))
            }
            return
        }

        target.parentFile?.let { parent ->
            if (!parent.exists() && !parent.mkdirs()) {
                throw IOException("无法创建目录: ${parent.absolutePath}")
            }
        }

        source.inputStream().use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        }
    }

    private fun setSystemTimeManual(epochMillis: Long): String {
        val seconds = epochMillis / 1000

        val commandCandidates = listOf(
            "date -s @$seconds",
            "toybox date -s @$seconds"
        )

        val errors = mutableListOf<String>()
        for (command in commandCandidates) {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            val exitCode = process.waitFor()
            if (exitCode == 0) {
                return "系统时间已尝试修改（root）"
            }
            errors.add("$command (exit=$exitCode)")
        }

        throw SecurityException(
            "无法直接修改系统时间。通常需要 root 或系统级权限。失败命令: ${errors.joinToString()}"
        )
    }

    private fun setSystemTimeAuto(enabled: Boolean): String {
        val hasSecureSettings = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        if (hasSecureSettings) {
            Settings.Global.putInt(
                contentResolver,
                Settings.Global.AUTO_TIME,
                if (enabled) 1 else 0
            )
            return if (enabled) "已设置为自动时间" else "已关闭自动时间"
        }

        val intent = Intent(Settings.ACTION_DATE_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return "没有系统级权限，已打开日期和时间设置页，请手动修改。"
    }

    private fun openApp(packageName: String): String {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: throw IllegalArgumentException("无法找到应用或没有启动入口: $packageName")
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(launchIntent)
        return "已打开应用: $packageName"
    }

    private fun searchApps(query: String): List<Map<String, String>> {
        val normalized = query.trim().lowercase()
        val apps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

        return apps
            .filter { app -> packageManager.getLaunchIntentForPackage(app.packageName) != null }
            .map { app ->
                mapOf(
                    "appName" to packageManager.getApplicationLabelSafe(app),
                    "packageName" to app.packageName
                )
            }
            .filter { app ->
                if (normalized.isEmpty()) {
                    true
                } else {
                    app["appName"]!!.lowercase().contains(normalized) ||
                        app["packageName"]!!.lowercase().contains(normalized)
                }
            }
            .sortedWith(
                compareBy<Map<String, String>> { it["appName"]!!.lowercase() }
                    .thenBy { it["packageName"]!! }
            )
            .take(200)
    }

    private fun PackageManager.getApplicationLabelSafe(app: ApplicationInfo): String {
        return try {
            getApplicationLabel(app).toString()
        } catch (_: Exception) {
            app.packageName
        }
    }
}
