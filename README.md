# 留白日记

安卓 + Windows 11 的 Flutter 原生应用，不是网页外壳。

## 当前状态

- 本地写作、修改、搜索、日期和心情、回收站与恢复。
- JSON 导入、导出；Android 使用系统分享面板保存备份，Windows 选择保存位置。
- 云端邮箱账号登录、注册和手动同步；同一项目同一账号，两端内容互通。
- 离线先保存在本机。同步遇到版本冲突时，保留云端原件并复制本地版本，标题带“冲突保留”；再次同步上传副本。
- **云端服务需要按下文配置。没有配置时仅本机保存，不会跨设备同步。**
- 安装包是否成功生成，以 Actions 的绿色结果和 Artifacts 为准，不代表已经做过真机测试。

## 下载测试安装包

打开仓库 **Actions → Build Android and Windows apps → 最新成功运行 → Artifacts**：

| 文件 | 用途 |
| --- | --- |
| LiubaiDiary-Android-Preview-APK | 解压，安装 app-debug.apk（预览版） |
| LiubaiDiary-Windows11-Installer | 解压，运行 LiubaiDiary-Windows11-Setup.exe |
| LiubaiDiary-Windows11-Portable | 解压整个文件夹，运行 liubai_diary.exe，不能只复制 exe |

需要登录 GitHub 下载 Actions 附件，保留 30 天，过期可手动重新运行工作流。
安卓预览版使用开发签名，不用于商店发布；CI 缓存失效可能使后续安装包签名变化，正式长期使用前要配置永久签名，不能用卸载解决签名冲突而丢失日记，请先导出备份。
Windows 安装包当前未购买代码签名证书。Windows x64，推荐 Windows 11。

## 配置两端云端互通（只需建一个项目）

1. 在 https://supabase.com/dashboard 创建你自己管理的 Supabase 项目。
2. 打开项目 **SQL Editor**，复制并运行仓库的 [backend/schema.sql](backend/schema.sql)。此脚本创建日记表、按用户隔离的读取策略和版本检查写入函数；重复运行不会删除日记。
3. 从项目 Connect / API 设置复制 **Project URL** 和 **Publishable key（或 legacy anon key）**。不要复制 `service_role`、`sb_secret_` 或数据库密码。
4. 在手机、电脑 App 的云朵按钮中，填入同一组 URL 和公钥，点击保存云端配置。
5. 在一端注册邮箱账号，按邮件提示确认，然后在两端用相同邮箱和密码登录。邮件确认跳转页面是否可用，不影响在完成邮箱确认后回 App 使用密码登录。
6. 本机已有日记时，在设置中选择“复制本机日记到当前账号”；明确确认后才会加入当前账号待同步队列。
7. 写完点击保存，再点击列表右上角同步。另一端也点击同步查看。当前不是实时共同编辑。

数据使用 HTTPS 传输和账号隔离，不提供端到端加密。项目管理员可以访问数据库。本机 JSON 数据未加密；登录令牌放在操作系统安全存储里，密码不保存在客户端。不要将日记备份提交到此公开仓库。
原 Sites 网页的数据不自动迁移；其导出格式不同，需要后续增加转换支持。

## 本地开发与自动构建

固定 Flutter 3.35.7，Java 17；Windows 构建需要 Visual Studio 的 Desktop development with C++ 工作负载。

```sh
python tool/prepare.py
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run
```

`tool/prepare.py` 使用 Flutter 官方模板生成 android/windows 平台目录（忽略提交），维护的 Dart 代码不会被覆盖。推送 main 或手动启动 Actions 会构建安卓 APK 和 Windows 安装包。公开仓库只保存代码；云端账号、日记和密码不写入仓库。

## 使用前验证

- 先用非隐私测试内容，在两台设备登录同一账号，测试新增、修改、删除和恢复后同步。
- 分别离线修改同一篇，再同步，确认双方文字均保留。
- 测试导出和导入；定期备份，卸载前先导出。
