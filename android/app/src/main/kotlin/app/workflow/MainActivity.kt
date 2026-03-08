package app.workflow

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "workflow_tool/atomics"
        private const val LAUNCH_EVENT_CHANNEL = "workflow_tool/launch_events"
        private const val ACTION_RUN_WORKFLOW = "app.workflow.RUN_WORKFLOW"
        private const val EXTRA_WORKFLOW_ID = "workflowId"
    }

    private var pendingLaunchWorkflowId: String? = null
    private var launchEventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLaunchWorkflowId = extractWorkflowIdFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val workflowId = extractWorkflowIdFromIntent(intent) ?: return
        pendingLaunchWorkflowId = workflowId
        launchEventSink?.success(workflowId)
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    launchEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    launchEventSink = null
                }
            })
    }

    private fun handleCall(call: MethodCall): Any {
        return when (call.method) {
            "deleteFolder" -> {
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("path 不能为空")
                ensureFileOperationPermission()
                deleteFolder(path)
            }

            "copyFolder" -> {
                val sourcePath = call.argument<String>("sourcePath")
                    ?: throw IllegalArgumentException("sourcePath 不能为空")
                val targetPath = call.argument<String>("targetPath")
                    ?: throw IllegalArgumentException("targetPath 不能为空")
                ensureFileOperationPermission()
                copyFolder(sourcePath, targetPath)
            }

            "createFolder" -> {
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("path 不能为空")
                ensureFileOperationPermission()
                createFolder(path)
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
            "createPinnedWorkflowShortcut" -> {
                val workflowId = call.argument<String>("workflowId")
                    ?: throw IllegalArgumentException("workflowId 不能为空")
                val workflowName = call.argument<String>("workflowName")
                    ?: throw IllegalArgumentException("workflowName 不能为空")
                createPinnedWorkflowShortcut(workflowId, workflowName)
            }
            "getInitialLaunchWorkflowId" -> {
                val workflowId = pendingLaunchWorkflowId
                pendingLaunchWorkflowId = null
                workflowId ?: ""
            }
            "canManageAllFilesAccess" -> {
                canManageAllFilesAccess()
            }
            "requestManageAllFilesAccess" -> {
                requestManageAllFilesAccess()
            }
            "setWifiEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                setWifiEnabled(enabled)
            }
            "toggleWifi" -> {
                toggleWifi()
            }
            "setBluetoothEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                setBluetoothEnabled(enabled)
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
            throw SecurityException("删除失败，可能没有目录写入权限: $path")
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

    private fun createFolder(path: String): String {
        val target = File(path)
        if (target.exists()) {
            return "文件夹已存在: $path"
        }
        if (target.mkdirs()) {
            return "创建成功: $path"
        }
        throw IOException("创建文件夹失败: $path")
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

    private fun createPinnedWorkflowShortcut(workflowId: String, workflowName: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            throw UnsupportedOperationException("Android 8.0 以下不支持固定桌面快捷方式")
        }
        val shortcutManager = getSystemService(ShortcutManager::class.java)
            ?: throw IllegalStateException("ShortcutManager 不可用")

        if (!shortcutManager.isRequestPinShortcutSupported) {
            throw UnsupportedOperationException("当前启动器不支持固定桌面快捷方式")
        }

        val shortcutIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_RUN_WORKFLOW
            putExtra(EXTRA_WORKFLOW_ID, workflowId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val shortcut = ShortcutInfo.Builder(this, "workflow_$workflowId")
            .setShortLabel(workflowName.take(20))
            .setLongLabel("执行工作流: $workflowName")
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(shortcutIntent)
            .build()

        val requested = shortcutManager.requestPinShortcut(shortcut, null)
        if (!requested) {
            throw IllegalStateException("系统未接受快捷方式请求")
        }
        return "已请求添加到桌面: $workflowName"
    }

    private fun extractWorkflowIdFromIntent(intent: Intent?): String? {
        if (intent == null) {
            return null
        }
        if (intent.action != ACTION_RUN_WORKFLOW) {
            return null
        }
        return intent.getStringExtra(EXTRA_WORKFLOW_ID)
    }

    private fun ensureFileOperationPermission() {
        if (!canManageAllFilesAccess()) {
            requestManageAllFilesAccess()
            throw SecurityException("请先授予所有文件访问权限后重试工作流。")
        }
    }

    private fun canManageAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager()
        }
        return true
    }

    private fun requestManageAllFilesAccess(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return "当前 Android 版本不需要所有文件访问权限。"
        }
        val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = android.net.Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            val fallbackIntent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallbackIntent)
        }
        return "已打开所有文件访问权限设置页，请授权后重试。"
    }

    private fun setWifiEnabled(enabled: Boolean): String {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: throw IllegalStateException("无法获取 WiFiManager")

        // Android 10+ 无法直接开关 WiFi，需要引导用户到设置页
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return "Android 10+ 限制直接控制 WiFi，已打开 WiFi 设置页，请手动${if (enabled) "开启" else "关闭"}"
        }

        // Android 9 及以下可以直接控制
        if (!wifiManager.isWifiEnabled && enabled) {
            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = true
            return "WiFi 已开启"
        } else if (wifiManager.isWifiEnabled && !enabled) {
            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = false
            return "WiFi 已关闭"
        }
        return "WiFi 状态未改变（当前已${if (enabled) "开启" else "关闭"}）"
    }

    private fun toggleWifi(): String {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: throw IllegalStateException("无法获取 WiFiManager")

        // Android 10+ 无法直接开关 WiFi，需要引导用户到设置页
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return "Android 10+ 限制直接控制 WiFi，已打开 WiFi 设置页，请手动切换"
        }

        // Android 9 及以下可以直接控制
        @Suppress("DEPRECATION")
        val newState = !wifiManager.isWifiEnabled
        wifiManager.isWifiEnabled = newState
        return "WiFi 已${if (newState) "开启" else "关闭"}"
    }

    private fun setBluetoothEnabled(enabled: Boolean): String {
        val bluetoothAdapter = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothManager?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        } ?: throw IllegalStateException("无法获取蓝牙适配器")

        // Android 12+ 需要蓝牙权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasPermission = checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            if (!hasPermission) {
                val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return "Android 12+ 需要蓝牙权限，已打开蓝牙设置页，请手动${if (enabled) "开启" else "关闭"}"
            }
        }

        // 尝试直接控制蓝牙
        return if (enabled) {
            if (!bluetoothAdapter.isEnabled) {
                val success = bluetoothAdapter.enable()
                if (success) "蓝牙已开启" else "蓝牙开启请求已发送"
            } else {
                "蓝牙已处于开启状态"
            }
        } else {
            if (bluetoothAdapter.isEnabled) {
                val success = bluetoothAdapter.disable()
                if (success) "蓝牙已关闭" else "蓝牙关闭请求已发送"
            } else {
                "蓝牙已处于关闭状态"
            }
        }
    }
}
