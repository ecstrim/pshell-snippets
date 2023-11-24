Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

public class InterceptKeys {
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;

    public static void Main() {
        _hookID = SetHook(_proc);
        Application.Run();
        UnhookWindowsHookEx(_hookID);
    }

    private static IntPtr SetHook(LowLevelKeyboardProc proc) {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule) {
            return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN) {
            int vkCode = Marshal.ReadInt32(lParam);
            if ((Control.ModifierKeys & Keys.Control) != 0 &&
                (Control.ModifierKeys & Keys.Shift) != 0 &&
                (Control.ModifierKeys & Keys.Alt) != 0 &&
                vkCode == (int)Keys.M) {
                RunPowershellScript();
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    private static void RunPowershellScript() {
    using (PowerShell PowerShellInstance = PowerShell.Create()) {
        PowerShellInstance.AddScript("Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force");  // Bypass execution policy for this session
        PowerShellInstance.AddScript("& 'X:\\Path\\Toggle-MikeMute.ps1'");  // Update the path to your script
        PowerShellInstance.Invoke();
    }
}


    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
}
"@ -ReferencedAssemblies "System.Windows.Forms" -Language CSharp

[InterceptKeys]::Main()
