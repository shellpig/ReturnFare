# Windows background-mode mechanism + guards for the ReturnFare UI simulation.
# Dot-sourced by run_ui_sim.ps1; keeps Win32 desktop/window concerns out of the launcher body.
#
# 機制：把背景模式的每個 Godot 行程開在一張獨立的 Windows desktop 上。
#
# 一張 desktop 是作業系統層級的隔離單位：視窗、前景視窗、輸入佇列都是 per-desktop 的。
# 開在別張 desktop 的視窗**不可能**出現在使用者眼前，也**不可能**成為使用者那張桌面的
# 前景視窗——這不是「我們趕在它前面把它藏起來」，是它壓根不在同一個空間裡。
#
# 為什麼不用搶時間的做法（都實測過，都不夠）：
#   override.cfg 寫 display/window/size/no_focus  → 編輯器版執行檔不載入 override.cfg，
#                                                   ProjectSettings 讀回來仍是 false
#   CLI --position -4000,-4000                    → Godot 會裁到螢幕範圍內，實際變成 (0,0)
#   ProcessStartInfo.WindowStyle = Hidden         → Godot 自己呼叫 ShowWindow(SW_SHOW)，
#                                                   STARTUPINFO 的提示不生效
#   launcher 搶在顯示前搬視窗並加 WS_EX_NOACTIVATE
#       → 位置那半有效，焦點那半無效；而且時序每次都不一樣，某些啟動裡「視窗建立」與
#         「取得前景」落在同一個取樣點內，根本沒有空檔可搶。競速贏不了。
#
# 實測（本機 RTX 4080、GL Compatibility）：獨立 desktop 上 Godot 仍取得硬體 OpenGL 3.3
# context，所以 viewport screenshot 這條證據鏈不受影響。
#
# ⚠️ 兩個編碼地雷，改本檔前先看：
#   1. 本檔必須存成帶 BOM 的 UTF-8。PowerShell 5.1 對無 BOM 的檔案以系統 ANSI（CP950）
#      解讀，中文註解會被拆壞，症狀是整檔安靜地少定義幾個函式，而且完全不報錯。
#   2. 下面的 C# 區塊一律只能有 ASCII。Add-Type 把 here-string 以 ANSI 落成暫存 .cs 再
#      編譯，中文註解在那裡會炸成一整排「修飾詞 extern 對此項目無效」，而且行號指向
#      完全無關的位置。C# 的說明一律寫在 PowerShell 註解這一側。

if (-not ("ReturnFareUiSimNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ReturnFareUiSimNative {
    public const string GodotWindowClass = "Engine";

    private const uint GENERIC_ALL = 0x10000000;
    private const uint CREATE_NO_WINDOW = 0x08000000;
    private const uint STILL_ACTIVE = 259;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr sa);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr h);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr h, out uint exitCode);

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);

    [DllImport("user32.dll")]
    private static extern bool EnumDesktopWindows(IntPtr desktop, EnumWindowsProc cb, IntPtr p);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr h, StringBuilder b, int n);

    public static IntPtr CreateIsolatedDesktop(string name) {
        return CreateDesktopW(name, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero);
    }

    public static bool DestroyIsolatedDesktop(IntPtr desktop) {
        return CloseDesktop(desktop);
    }

    public static PROCESS_INFORMATION StartOnDesktop(string desktopName, string application, string commandLine, string workingDirectory) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = desktopName;
        PROCESS_INFORMATION pi;
        StringBuilder cmd = new StringBuilder(commandLine, 32768);
        if (!CreateProcessW(application, cmd, IntPtr.Zero, IntPtr.Zero, false, CREATE_NO_WINDOW, IntPtr.Zero, workingDirectory, ref si, out pi)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        return pi;
    }

    public static int TryGetExitCode(IntPtr processHandle) {
        uint code;
        if (!GetExitCodeProcess(processHandle, out code)) { return -1; }
        if (code == STILL_ACTIVE) { return -1; }
        return unchecked((int)code);
    }

    public static void ReleaseProcessHandles(PROCESS_INFORMATION pi) {
        if (pi.hThread != IntPtr.Zero) { CloseHandle(pi.hThread); }
        if (pi.hProcess != IntPtr.Zero) { CloseHandle(pi.hProcess); }
    }

    private static string ClassOf(IntPtr hwnd) {
        StringBuilder b = new StringBuilder(256);
        GetClassNameW(hwnd, b, b.Capacity);
        return b.ToString();
    }

    private static string[] Collect(IntPtr desktop, int pid, bool useDesktop) {
        List<string> found = new List<string>();
        EnumWindowsProc cb = delegate(IntPtr hwnd, IntPtr lp) {
            uint owner;
            GetWindowThreadProcessId(hwnd, out owner);
            if (owner == (uint)pid) { found.Add(ClassOf(hwnd)); }
            return true;
        };
        if (useDesktop) { EnumDesktopWindows(desktop, cb, IntPtr.Zero); }
        else { EnumWindows(cb, IntPtr.Zero); }
        return found.ToArray();
    }

    public static string[] WindowsOnInteractiveDesktop(int pid) { return Collect(IntPtr.Zero, pid, false); }

    public static string[] WindowsOnIsolatedDesktop(IntPtr desktop, int pid) { return Collect(desktop, pid, true); }

    public static uint GetForegroundProcessId() {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) { return 0; }
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        return pid;
    }
}
"@
}


## 建立本次執行專用的隔離 desktop。名稱帶 PID 與亂數，同機平行跑兩套不會互撞。
function Enter-UiSimIsolatedDesktop {
    $name = "ReturnFareUiSim_{0}_{1}" -f $PID, ([Guid]::NewGuid().ToString("N").Substring(0, 8))
    $handle = [ReturnFareUiSimNative]::CreateIsolatedDesktop($name)
    if ($handle -eq [IntPtr]::Zero) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "CreateDesktop failed ($code): $((New-Object ComponentModel.Win32Exception($code)).Message)"
    }
    return [pscustomobject]@{ Name = $name; Handle = $handle }
}


## desktop 在最後一個 handle 關閉、且上面沒有行程時自動消滅：不落地、不跨重開機。
## 就算 launcher 被硬砍掉也不會留下要清的殘留——這是它比 override.cfg 好的地方。
function Exit-UiSimIsolatedDesktop {
    param($Desktop)
    if ($null -eq $Desktop) { return }
    [void][ReturnFareUiSimNative]::DestroyIsolatedDesktop($Desktop.Handle)
}


function Start-UiSimProcessOnDesktop {
    param(
        $Desktop,
        [string]$FileName,
        [string]$Arguments,
        [string]$WorkingDirectory
    )
    $commandLine = "`"{0}`" {1}" -f $FileName, $Arguments
    return [ReturnFareUiSimNative]::StartOnDesktop($Desktop.Name, $FileName, $commandLine, $WorkingDirectory)
}


## 背景模式的一次巡邏。兩條違規都應該是結構上不可能發生的；真的發生代表隔離破了，
## 這時候寧可整套紅掉，也不要讓上百個視窗跳到使用者臉上。
##
##   1. 該行程的視窗出現在使用者那張 desktop 的枚舉結果裡  → 畫面上看得到它
##   2. 該行程成為使用者那張 desktop 的前景                → 打字會被吃掉
##
## 另外回報有沒有真的在隔離 desktop 上看到 Godot 主視窗（類別 Engine）。
## 沒看到就代表這一輪守衛其實什麼都沒驗到，那是假綠，呼叫端要當失敗處理。
function Invoke-UiSimBackgroundPatrol {
    param([int]$ProcessId, $Desktop)

    $violations = New-Object System.Collections.Generic.List[string]

    $leaked = @([ReturnFareUiSimNative]::WindowsOnInteractiveDesktop($ProcessId))
    if ($leaked.Count -gt 0) {
        $violations.Add("window(s) leaked onto the interactive desktop: $((($leaked | Select-Object -Unique) -join ', '))")
    }
    if ([int][ReturnFareUiSimNative]::GetForegroundProcessId() -eq $ProcessId) {
        $violations.Add("Godot process $ProcessId became the foreground process")
    }

    $isolated = @([ReturnFareUiSimNative]::WindowsOnIsolatedDesktop($Desktop.Handle, $ProcessId))

    return [pscustomobject]@{
        EngineWindowSeen = ($isolated -contains [ReturnFareUiSimNative]::GodotWindowClass)
        Violations       = @($violations)
    }
}
