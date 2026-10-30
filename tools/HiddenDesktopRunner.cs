// HiddenDesktopRunner — lance un processus sur un bureau Windows secondaire.
//
// Le bureau secondaire est créé dans la session de l'utilisateur, n'est jamais
// affiché (pas de SwitchDesktop), et disparaît quand plus aucun processus ne
// l'utilise. Les fenêtres du processus y vivent : elles ne peuvent ni
// apparaître sur le bureau de l'utilisateur ni lui voler le focus clavier.
// Aucun réglage système n'est modifié.
//
// Le lanceur mesure aussi ce qu'il observe sur le bureau de l'utilisateur
// (fenêtres visibles du processus, fenêtre au premier plan) pour que le
// rapport dise ce qui s'est réellement passé.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class HiddenDesktopRunner
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktopW(string name, IntPtr dev, IntPtr mode, int flags, uint access, IntPtr sa);
    [DllImport("user32.dll", SetLastError = true)] static extern bool CloseDesktop(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags,
        IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);

    public class Result
    {
        public string Error;
        public uint ExitCode;
        public bool TimedOut;
        public int ProcessId;
        public double DurationSec;
        public bool ProcessWindowInForeground;   // une fenêtre Studio a-t-elle pris le premier plan de l'utilisateur ?
        public int MaxProcessWindowsOnUserDesktop; // fenêtres Studio visibles sur le bureau de l'utilisateur
        public bool ForegroundChanged;           // le premier plan a changé (peut venir de l'utilisateur lui-même)
        public bool HiddenDesktop;
    }

    static HashSet<uint> studioPids = new HashSet<uint>();

    static int VisibleWindowsOf(string processName)
    {
        int count = 0;
        EnumWindows((h, p) =>
        {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (IsWindowVisible(h) && IsWatched(wp, processName)) count++;
            return true;
        }, IntPtr.Zero);
        return count;
    }

    // Studio peut lancer des processus enfants (clients de test multijoueur) :
    // on surveille tous les processus portant le même nom démarrés après le lancement.
    static bool IsWatched(uint pid, string processName)
    {
        if (studioPids.Contains(pid)) return true;
        try
        {
            var p = System.Diagnostics.Process.GetProcessById((int)pid);
            return p.ProcessName.Equals(processName, StringComparison.OrdinalIgnoreCase) && p.StartTime >= started;
        }
        catch { return false; }
    }

    static DateTime started;

    public static Result Run(string commandLine, int timeoutMs, bool hidden, string desktopName, string processName)
    {
        var r = new Result { HiddenDesktop = hidden };
        IntPtr desk = IntPtr.Zero;
        if (hidden)
        {
            desk = CreateDesktopW(desktopName, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero);
            if (desk == IntPtr.Zero) { r.Error = "CreateDesktop: " + Marshal.GetLastWin32Error(); return r; }
        }
        try
        {
            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            if (hidden) si.lpDesktop = desktopName;
            PROCESS_INFORMATION pi;
            IntPtr fgBefore = GetForegroundWindow();
            started = DateTime.Now.AddSeconds(-1);
            var t0 = DateTime.UtcNow;
            if (!CreateProcessW(null, new StringBuilder(commandLine, 32768), IntPtr.Zero, IntPtr.Zero, false, 0,
                    IntPtr.Zero, null, ref si, out pi))
            {
                r.Error = "CreateProcess: " + Marshal.GetLastWin32Error();
                return r;
            }
            r.ProcessId = pi.dwProcessId;
            studioPids.Clear();
            studioPids.Add((uint)pi.dwProcessId);
            var deadline = t0.AddMilliseconds(timeoutMs);
            while (WaitForSingleObject(pi.hProcess, 250) != 0)
            {
                IntPtr fg = GetForegroundWindow();
                if (fg != fgBefore) r.ForegroundChanged = true;
                uint fgPid; GetWindowThreadProcessId(fg, out fgPid);
                if (IsWatched(fgPid, processName)) r.ProcessWindowInForeground = true;
                int visible = VisibleWindowsOf(processName);
                if (visible > r.MaxProcessWindowsOnUserDesktop) r.MaxProcessWindowsOnUserDesktop = visible;
                if (DateTime.UtcNow > deadline)
                {
                    TerminateProcess(pi.hProcess, 99);
                    WaitForSingleObject(pi.hProcess, 10000);
                    r.TimedOut = true;
                    break;
                }
            }
            uint code; GetExitCodeProcess(pi.hProcess, out code);
            r.ExitCode = code;
            r.DurationSec = Math.Round((DateTime.UtcNow - t0).TotalSeconds, 1);
            CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
            return r;
        }
        finally
        {
            if (desk != IntPtr.Zero) CloseDesktop(desk);
        }
    }
}
