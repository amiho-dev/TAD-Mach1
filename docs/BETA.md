# Mach1 (by TAD) - Beta Information

This repository currently ships a beta-stage two-phase patching model:

- Stage 1: Native PowerShell Orchestrator (WinPE/WinRE compatible)
- Stage 2: WinRE Engine (offline registry surgeon)

## Risk Notice

- BETA - Use at your own risk.
- Stage 1 requires Administrator permissions to launch and will self-elevate.
- Stage 1 enforces a mandatory backup gate before "Reboot To Patch" is allowed.
- Stage 2 has fail-safe behavior: if offline hive mounting fails, it aborts and reboots to avoid any boot-loop scenario.

## Current Release

- M1.0415.001.BF

## Branding

- All logs and runtime headers use: Mach1 (by TAD)
