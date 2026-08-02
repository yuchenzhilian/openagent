# OpenAgent Android 真机一键冒烟测试 & 安装助手
# 用法 (在项目根目录 PowerShell 7+ 执行):
#   pwsh ./scripts/android_smoke_test.ps1
#
# 会依次做:
#   1. 检查 adb 环境 + 设备连接 (USB 调试)
#   2. 安装最新 debug APK (若不存在提示先 build)
#   3. 打印一张用户应当在真机上手动走一遍的冒烟验证 Checklist
#      （每一步附带预期现象 & 对应 Agent 工具名，方便调试定位）

param(
  [string]$ApkPath = $(Join-Path $PSScriptRoot ".." "build\app\outputs\flutter-apk\app-debug.apk"),
  [string]$PackageName = "com.openagent.openagent",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

function Step($title) {
  Write-Host ""
  Write-Host "==> $title" -ForegroundColor Cyan
}

function Ok($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [XX] $m" -ForegroundColor Red }

Step "1/4 检查 Android SDK / adb"
$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
  Fail "找不到 adb。请把 Android SDK platform-tools 加入 PATH，或在 Android Studio → SDK Manager 下载。"
  exit 1
}
Ok "adb 可用: $($adb.Source)"

Step "2/4 检查设备连接"
$devicesRaw = & adb devices
$devices = $devicesRaw | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] }
if (-not $devices -or $devices.Count -eq 0) {
  Fail "未检测到任何 adb devices。请插上手机并在手机 → 设置 → 开发者选项 → USB 调试 打开。"
  Warn "adb devices 输出如下:"
  $devicesRaw | ForEach-Object { Write-Host "      $_" }
  exit 2
}
$deviceCount = @($devices).Count
$deviceList = @($devices) -join ", "
Ok "检测到 $deviceCount 台设备: $deviceList"

Step "3/4 安装 Debug APK"
$apkResolved = Resolve-Path $ApkPath -ErrorAction SilentlyContinue
if (-not $apkResolved) {
  if ($SkipInstall) {
    Warn "APK 不存在且 -SkipInstall 已指定，跳过安装。"
  } else {
    Fail "未找到 APK：$ApkPath"
    Write-Host "  请先在项目根目录执行："
    Write-Host "      flutter build apk --debug"
    Write-Host "  构建完成后再跑本脚本，或传 -ApkPath 指向 APK 文件。"
    exit 3
  }
} else {
  if (-not $SkipInstall) {
    $apkSizeMB = [math]::Round((Get-Item $apkResolved).Length / 1MB, 1)
    Ok "APK 就绪 (${apkSizeMB} MB): $apkResolved"
    Write-Host "  正在卸载旧包 (若存在) 后重新安装..."
    & adb uninstall $PackageName 2>&1 | Out-Null
    $inst = & adb install -r $apkResolved 2>&1
    if ($LASTEXITCODE -ne 0 -or ($inst -join "`n") -notmatch "Success") {
      Fail "APK 安装失败。adb 输出:"
      $inst | ForEach-Object { Write-Host "      $_" }
      exit 4
    }
    Ok "APK 安装成功 (package=$PackageName)"
    Write-Host "  启动主 Activity..."
    & adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
  }
}

Step "4/4 真机冒烟测试 Checklist (请在手机上按顺序执行，并对勾通过项)"
Write-Host ""
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  A. 基础 & LLM 加载 (文本 Agent 主循环验证)" -ForegroundColor Yellow
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  [ ] A1 首次打开 App 能正常进入首页，无闪退、无红屏"
Write-Host "  [ ] A2 「模型市场」下载 Qwen3-0.6B-MNN (或任意文本模型)"
Write-Host "  [ ] A3 在聊天页切换到刚下载的模型 → 提示「正在加载…」几秒后完成"
Write-Host "  [ ] A4 发送文本: 「介绍一下你自己, 3句话」，模型以 ~10 t/s 速度流式输出正确答案"
Write-Host "  [ ] A5 对话历史被正确保留；清空会话按钮可以清空"
Write-Host ""
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  B. Android 自动化权限引导页" -ForegroundColor Yellow
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  [ ] B1 聊天页右上角 ⚙ → 进入「自动化权限引导」页，能正常渲染 (不崩溃)"
Write-Host "  [ ] B2 顶部合规风险提示卡片可点击「我已了解」折叠"
Write-Host "  [ ] B3 4 张权限卡片全部可见: L1 无障碍 / L2 Shizuku / 辅助 应用使用统计 / L3 截图"
Write-Host "  [ ] B4 点击 L1「无障碍服务」卡片 → 跳转到系统无障碍设置，能看到并开启 OpenAgent 无障碍服务"
Write-Host "  [ ] B5 返回引导页 → L1 状态自动变绿  已授权 (说明 MethodChannel refreshStatus & 2s 轮询生效)"
Write-Host "  [ ] B6 点击辅助「应用使用统计」→ 跳转对应设置页 → 开启 OpenAgent 的使用访问权限 → 返回后卡片变绿"
Write-Host "  [ ] B7 (可选) 安装手机端 Shizuku App: https://shizuku.rikka.app/zh-hans/download/ 并授权 → L2 变绿"
Write-Host "  [ ] B8 权限摘要卡片根据授权数量正确显示 绿/橙/蓝 状态色"
Write-Host ""
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  C. Agent 模式 (关键: 必须先完成 A2~A4 + B1~B5 + B6 再来测试)" -ForegroundColor Yellow
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  [ ] C1 聊天页 → 对话设置中打开「启用 Agent 模式」和「Android 自动化」两个开关"
Write-Host "  [ ] C2 发送指令: 「帮我打开「设置」, 然后回到桌面」"
Write-Host "         预期: Agent 先 <tool_call> android_get_top_app 确认当前包名"
Write-Host "                  → android_open_app 跳 com.android.settings"
Write-Host "                  → android_wait(2s)"
Write-Host "                  → android_press_key(key=home) 回到桌面"
Write-Host "                  → 最终回答告知操作完成"
Write-Host "  [ ] C3 (微信 L1 基础操作) 发送: 「打开微信, 点一下底部的「我」tab」"
Write-Host "         预期: Agent 用 get_top_app / android_dump_ui 先看界面"
Write-Host "                  → 找到底部tab匹配文字并 android_click_by_text('我')"
Write-Host "                  → 微信确实切换到「我」页面 (即使 ACTION_CLICK 失败也 fallback 坐标点击，应能命中)"
Write-Host "  [ ] C4 (抖音 feed 识别) 先手动打开抖音首页停在推荐Feed（控件多为 ImageView 无文字）"
Write-Host "         发: 「告诉我当前抖音界面能看到什么，然后轻轻向上滑一下看下一条视频」"
Write-Host "         预期: Agent dump_ui 返回很少 → 规则 F 触发"
Write-Host "                  → 先 android_screenshot 存 PNG"
Write-Host "                  → android_vision_analyze (若下载了 Omni) 看懂图片"
Write-Host "                  → 用 android_swipe 做上滑 400px"
Write-Host "  [ ] C5 (gshell 指令, 需要 Shizuku 授权) 发送: "
Write-Host "         「通过 shell 查一下我的设备当前电量百分比」"
Write-Host "         预期: android_gshell(dumpsys battery | grep level)"
Write-Host "                  → 输出数字与手机系统状态栏一致"
Write-Host "  [ ] C6 (权限查询) 发送: 「检查一下你现在的自动化权限都开了哪些」"
Write-Host "         预期: Agent 调 android_get_permission_status"
Write-Host "                  → 返回 4 行状态 (L1/L2/L3/辅助)，与引导页显示保持一致"
Write-Host ""
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  D. 多模态 / Omni VLM （需要在模型市场下载任一 Omni 模型后再做）" -ForegroundColor Yellow
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "  [ ] D1 切到 Omni 多模态模型，加载成功"
Write-Host "  [ ] D2 聊天里 + 相册 → 选一张手机照片 → 发送「描述这张图」, Omni 能看懂图片文字"
Write-Host "  [ ] D3 回到 Agent C4 场景，VLM 工具的分析结果出现在 agent_run 的思考链中"
Write-Host ""
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkGreen
Write-Host "  完成以上全部 OK 后, 你的 OpenAgent + Android 自动化 就真的能操手机了 🎉"
Write-Host "  出问题？把以下内容贴到开发者处: "
Write-Host "    1) flutter analyze 输出"
Write-Host "    2) 失败步骤的 flutter log / adb logcat 关键堆栈"
Write-Host "    3) 对应 Checklist 项编号" -ForegroundColor Green
Write-Host " --------------------------------------------------------------" -ForegroundColor DarkGreen
Write-Host ""

# 顺手把 adb logcat 清理与实时抓取的命令提示打印出来
Write-Host "小提示: 想实时看 App 日志 (排查崩溃用)，新开一个终端跑:"
Write-Host "  adb logcat -c ; adb logcat --pid=`$(adb shell pidof -s $PackageName) OpenAgent:* flutter:* *:E"
Write-Host ""
exit 0
