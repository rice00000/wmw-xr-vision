# Quest 3 一键工具：在电脑上构建 / 安装 / 启动 / 看日志 / 截屏 / 按键，不需要戴头显。
# 用法:  tools\quest.cmd <命令> [参数]      （quest.cmd 会自动绕过 PowerShell 执行策略）
#   wake     唤醒 Quest（伪造"已戴上"信号，头显放桌上也能运行 VR 应用）
#   sleep    取消伪造，恢复正常佩戴传感器
#   build    用 Godot 导出 debug APK 到 build\xrvision-quest3.apk
#   install  安装 APK 到 Quest
#   run      唤醒并以 VR 方式启动游戏（先强制停止旧进程，清空并放大日志缓冲）
#   stop     停止游戏
#   log      实时显示 Godot 日志（Ctrl+C 退出）
#   logdump  打印最近的 Godot / OpenXR 日志一次
#   shot     截屏到 build\quest-screen.png（双眼画面）
#   key      发送按键，例如 key ENTER / key BACK
#   mirror   打开 scrcpy 镜像窗口
#   all      build + install + run + logdump
param([Parameter(Position = 0)][string]$Command = 'all', [Parameter(Position = 1)][string]$Arg = '')

$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $PSScriptRoot
$Godot   = 'D:\Program Files\Portables\Godot_v4.7.2-stable_win64_console.exe'
$Package = 'com.example.xrvision'
$Preset  = 'Meta Quest 3'
$OutDir  = Join-Path $Project 'build'
$ApkName = 'xrvision-quest3.apk'
$Apk     = Join-Path $OutDir $ApkName
$env:JAVA_HOME    = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot'
# SDK 必须在 D:\，不能在 AppData：Claude 桌面应用里写进 AppData 的文件会被 MSIX 虚拟化，
# Godot 编辑器看不到，Android 一键部署按钮就不会出现。
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:ANDROID_USER_HOME = "$env:USERPROFILE\.android"
# 脚本、scrcpy、Godot 编辑器统一用 SDK 里的 adb：不同版本的 adb 会互相杀掉对方的服务，导致 Quest 反复断开。
$env:PATH = "$env:ANDROID_HOME\platform-tools;$env:PATH"
$env:ADB  = "$env:ANDROID_HOME\platform-tools\adb.exe"

$GodotTags = @('godot:V', 'Godot:V', 'GodotActivity:V', 'AndroidRuntime:E', 'DEBUG:E')

function Wake {
    adb shell am broadcast -a com.oculus.vrpowermanager.prox_close | Out-Null
    Start-Sleep -Seconds 2
    adb shell dumpsys power | Select-String 'mWakefulness='
}

function Build {
    python (Join-Path $Project 'tools\bake_speech.py')
    if ($LASTEXITCODE -ne 0) { throw '语音资源生成失败，已停止导出。' }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    if (Test-Path $Apk) { Remove-Item $Apk -Force }
    $log = Join-Path $OutDir 'export.log'
    $err = Join-Path $OutDir 'export.err.log'
    # Godot 调 gradlew 后会一直读它的输出管道；gradle 守护进程继承了这个管道且不退出，导致 Godot 导出完也挂着不退出。
    # 所以：1) 关掉 gradle 守护进程；2) 看到 "[ DONE ] export" 后主动结束 Godot。
    $env:GRADLE_OPTS = '-Dorg.gradle.daemon=false'
    $argList = @('--headless', '--path', ('"' + $Project + '"'), '--export-debug', ('"' + $Preset + '"'), ('build/' + $ApkName))
    # 首次导出：自动安装 Android 构建模板（android/ 已被 .gitignore 忽略）
    if (-not (Test-Path (Join-Path $Project 'android\build'))) { $argList = @('--install-android-build-template') + $argList }
    $proc = Start-Process -FilePath $Godot -ArgumentList $argList -RedirectStandardOutput $log -RedirectStandardError $err -NoNewWindow -PassThru
    $deadline = (Get-Date).AddMinutes(20)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $done = (Test-Path $Apk) -and ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match 'DONE.*export')
        if ($done) {
            Start-Sleep -Seconds 2
            if (-not $proc.HasExited) { taskkill /PID $proc.Id /T /F 2>&1 | Out-Null }
            break
        }
    }
    Get-Content $log, $err -ErrorAction SilentlyContinue | Select-String -Pattern 'ERROR|error:|FAILED|What went wrong' | Select-Object -Last 30
    if (-not (Test-Path $Apk)) { throw "APK 没有生成，完整日志见 $log 和 $err" }
    Get-Item $Apk | Select-Object FullName, Length, LastWriteTime
}

function Install { adb install -r -d $Apk }

function Run {
    Wake
    adb shell am force-stop $Package
    adb logcat -G 16M
    adb logcat -c
    adb shell am start -a android.intent.action.MAIN -c com.oculus.intent.category.VR -n "$Package/com.godot.game.GodotAppLauncher" | Select-String 'Status|TotalTime'
    Start-Sleep -Seconds 8
    Write-Output ("PID=" + (adb shell pidof $Package))
}

function LogDump {
    adb logcat -d -v time -s $GodotTags | Select-Object -Last 100
    Write-Output '--- OpenXR / 佩戴状态'
    adb logcat -d -v time | Select-String -Pattern 'OpenXR_SessionImpl|Mounted state|isUserPresent|SessionState' | Select-Object -Last 15
}

function Shot {
    $out = Join-Path $OutDir 'quest-screen.png'
    adb shell screencap -p /sdcard/quest-screen.png | Out-Null
    adb pull /sdcard/quest-screen.png $out | Out-Null
    Get-Item $out | Select-Object FullName, Length
}

switch ($Command) {
    'wake'    { Wake }
    'sleep'   { adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable }
    'build'   { Build }
    'install' { Install }
    'run'     { Run }
    'stop'    { adb shell am force-stop $Package }
    'log'     { adb logcat -v time -s $GodotTags }
    'logdump' { LogDump }
    'shot'    { Shot }
    'key'     { adb shell input keyevent ('KEYCODE_' + $Arg.ToUpper().Replace('KEYCODE_', '')) }
    'mirror'  { scrcpy --no-audio --max-size 1600 --window-title 'Quest 3' }
    'all'     { Build; Install; Run; LogDump }
    default   { Write-Output "未知命令: $Command"; Get-Content $PSCommandPath -TotalCount 15 }
}
