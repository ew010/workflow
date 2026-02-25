# Android Workflow Tool (Flutter)

一个可在安卓端执行工作流的工具。每个工作流由一个或多个原子操作组成，并可本地保存后重复执行。

## 已实现的原子操作

1. 删除指定文件夹
2. 复制指定文件夹到指定位置
3. 设置系统时间
   - 自动设置时间
   - 手动设置时间（尝试 root 命令）
4. 打开指定 App（按包名）

## 功能说明

- 创建/编辑/删除工作流
- 在工作流中添加多个原子操作
- 支持执行前确认开关
- 支持失败策略：失败即中断 / 失败后继续
- 本地持久化保存（`shared_preferences`）
- 一键执行整个工作流，按顺序逐步执行并显示日志

## 本地运行

```bash
flutter pub get
flutter run
```

## GitHub Actions 部署

已提供工作流文件：`.github/workflows/android-ci.yml`

- 在 `main` 分支 push 或 PR 时：
  - `flutter analyze`
  - `flutter test`
  - `flutter build apk --release`
  - 上传 APK 为构建产物
- 当推送 tag（例如 `v1.0.0`）时：
  - 自动创建 GitHub Release
  - 附加 `app-release.apk`

## 安卓权限与限制

- 文件删除/复制需要目标路径可访问。
- 打开 App 需要可解析到目标包名的启动入口。
- 修改系统时间在大多数普通设备上受限：
  - 手动改时间通常需要 `root` 或系统级权限。
  - 自动改时间通常需要 `WRITE_SECURE_SETTINGS`（系统权限）。
  - 无权限时会自动打开系统“日期和时间”设置页供手动操作。
