# Mach1 (by TAD) - Release Naming

## Current Release

- Mach1.0416.500.BF
- Type: Bug Fix (BF)
- Notes:
	- Full WPF UI redesign with responsive card layout
	- Auto light/dark theme based on system preference
	- Corrected Windows 11 display labeling for 10.0.26200+ kernels
	- Added GitHub release updater with automatic download and installer launch for EXE/MSI assets

Release tags are sorted and named in the following format:

M1.MMDD.Versionnumber.XX

Example:

- M1.0415.001.BF

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
