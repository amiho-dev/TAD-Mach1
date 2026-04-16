# TAD-Mach1

Mach1 (by TAD) is a two-stage Windows optimization workflow:

1. Stage 1: Native PowerShell Orchestrator (WinPE/WinRE compatible)
2. Stage 2: WinRE Engine (offline cold patching surgeon)

## Architecture

### Stage 1 - Windows Orchestrator

- Basic installer logic initializes C:\Mach1 with:
	- C:\Mach1\Config
	- C:\Mach1\Logs
	- C:\Mach1\WinRE
- Dashboard-style terminal UI with dedicated toggles for:
	- Kernel/Timer Tweaks (BCDEDIT)
	- Service Hardening (LTSC-oriented)
	- Game Optimization (CS2)
- Enforced Administrator requirement at launch.
- Prominent BETA banner and mandatory backup gate:
	- "BETA - Use at your own risk"
	- mandatory Create Backup workflow before patch mode
- Reboot-to-patch workflow:
	1. Save selected modules to settings.xml
	2. Add session handshake metadata (SessionId + release tag + prep timestamp)
	3. Inject startup script into WinRE image via winpeshl.ini
	4. Arm one-time WinRE boot with reagentc /boottore
	5. Reboot with shutdown /r /t 0

### Stage 2 - WinRE Engine

- High-contrast CLI style with progress bar and verbose toggle.
- Offline execution flow:
	1. Detect Windows partition.
	2. Mount offline hives: SYSTEM, SOFTWARE, NTUSER.DAT.
	3. Read settings.xml from C:\Mach1\Config.
	4. Validate handshake using patch.pending and settings SessionId/release.
	5. Apply selected cold tweaks while OS is offline.
- Verbose mode prints key-level operations in real time.
- Auto-finalize:
	- unload hives
	- clear pending startup trigger
	- write bridge result to C:\Mach1\Config\last-winre-result.json
	- reboot back to live Windows

## Technical Guardrails

- Error handling is fail-safe: if hive mounting fails, engine aborts and reboots.
- W10 LTSC focus guard is included:
	- Win11-specific appx/telemetry removal tracks are skipped on Windows 10 LTSC.
- Branding is consistent in logs and headers:
	- Mach1 (by TAD)

## Project Layout

- Mach1.Orchestrator.sln
- src/Mach1.Orchestrator
	- previous WPF orchestrator implementation
	- installer, backup, settings, WinRE orchestration services
- src/Mach1.Setup
	- UI-based cumulative installer for main system and recovery engine
- scripts/WinReEngine.ps1
	- Stage 2 offline patch engine used inside WinRE
- scripts/Build-CUInstaller.ps1
	- builds complete single-file UI installer with embedded payload
- Mach1.ps1
	- primary native PowerShell Stage 1 orchestrator

## Run (Windows)

Use an elevated PowerShell session:

1. Navigate to the repository root.
2. Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Mach1.ps1`
3. If not elevated already, Mach1 relaunches itself as Administrator.

## Release Naming

Release tags follow this format:

M1.MMDD.Versionnumber.XX

Example:

- Mach1.04166.501.CU

## Build Complete Installer (Windows)

1. Open elevated PowerShell in the repository root.
2. Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-CUInstaller.ps1`
3. Installer output: `artifacts\installer\Mach1.Setup.exe`

Suffix examples:

- BF = Bug Fix
- CU = Cumulative Update

See docs/RELEASES.md for sorting and suffix guidance.

## Beta Information

See docs/BETA.md for risk notice and current beta constraints.