# Sets the Windows volume of the default playback device (speakers/headphones)
# to 100% and unmutes it, through the Windows Core Audio API (no extra software).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File set-volume-max.ps1
#        or dot-source it and call Set-VolumeMax. Prints the device's volume afterwards.

if (-not ('StudyAudio.Volume' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace StudyAudio {
  [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr p);
    int UnregisterControlChangeNotify(IntPtr p);
    int GetChannelCount(out uint n);
    int SetMasterVolumeLevel(float db, Guid ctx);
    int SetMasterVolumeLevelScalar(float level, Guid ctx);
    int GetMasterVolumeLevel(out float db);
    int GetMasterVolumeLevelScalar(out float level);
    int SetChannelVolumeLevel(uint ch, float db, Guid ctx);
    int SetChannelVolumeLevelScalar(uint ch, float level, Guid ctx);
    int GetChannelVolumeLevel(uint ch, out float db);
    int GetChannelVolumeLevelScalar(uint ch, out float level);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, Guid ctx);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
  }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
  }
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int flow, int mask, out IntPtr devices);
    int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice device);
  }
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }
  public static class Volume {
    static IAudioEndpointVolume Endpoint() {
      var en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
      IMMDevice dev;
      Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0, 1, out dev)); // render, multimedia
      var iid = typeof(IAudioEndpointVolume).GUID;
      object o;
      Marshal.ThrowExceptionForHR(dev.Activate(ref iid, 23, IntPtr.Zero, out o)); // CLSCTX_ALL
      return (IAudioEndpointVolume)o;
    }
    public static void Set(float level, bool mute) {
      var v = Endpoint();
      Marshal.ThrowExceptionForHR(v.SetMasterVolumeLevelScalar(level, Guid.Empty));
      Marshal.ThrowExceptionForHR(v.SetMute(mute, Guid.Empty));
    }
    public static void SetMax() { Set(1.0f, false); }
    public static int Percent() { float l; Endpoint().GetMasterVolumeLevelScalar(out l); return (int)Math.Round(l * 100); }
    public static bool Muted() { bool m; Endpoint().GetMute(out m); return m; }
  }
}
'@
}

function Set-VolumeMax {
  [StudyAudio.Volume]::SetMax()
  $state = if ([StudyAudio.Volume]::Muted()) { 'muted' } else { 'not muted' }
  Write-Host "Windows volume: $([StudyAudio.Volume]::Percent())%, $state"
}

if ($MyInvocation.InvocationName -ne '.') { Set-VolumeMax }
