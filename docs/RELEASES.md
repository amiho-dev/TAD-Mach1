# Mach1 (by TAD) - Release Naming

## Current Release

- Mach1.04166.501.CU
- Type: Cumulative Update (CU)
- Notes:
	- Added SYS and RE session handshake (SessionId + release validation)
	- Added WinRE-to-SYS completion bridge file (`last-winre-result.json`)
	- Added full UI installer app (`Mach1.Setup`) for main system and recovery engine components
	- Bundled full payload inside installer publish output and enabled updater-driven `-update` mode
	- Added installer packaging script: `scripts/Build-CUInstaller.ps1`
	- Published complete single-file installer payload: `artifacts/installer/Mach1.Setup.exe`

Release tags are sorted and named in the following format:

M1.MMDD.Versionnumber.XX

Example:

- Mach1.04166.501.CU

## Segment Meaning

- M1: Mach1 major stream
- MMDD: Month and day of the release cut
- Versionnumber: Three-digit incremental number in that stream
- XX: Update type suffix

## Suggested Suffixes

- BF: Bug Fix
- CU: Cumulative Update
- HF: Hotfix
- RC: Release Candidate

## Sort Rule

Sort by:

1. MMDD ascending
2. Versionnumber ascending
3. Suffix lexicographic when date and number are equal
