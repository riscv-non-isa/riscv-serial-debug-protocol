# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## Releases on old gitlab repository

Prior to moving to github and a new version of the template, this project was maintained in the [riscv-rsdp-spec repository on gitlab](https://gitlab.com/lauterbach/riscv-rsdp-spec).
Releases below are versioned using the old semantic versioning scheme.

### [0.1.5] - 2026-10-20
- Clarify idle cycles between transactions

### [0.1.4] - 2026-10-20
- Clarify escape sequence encoding
- Remove TRN fields where neither side drives in order to not depend on pull resistors
- Define how extensions can use DMI-internal bus addresses and TT encodings

### [0.1.3] - 2026-08-25
- Add rationale behind arbitrary time constants in RSDPxSP
- In RSDPxSP, consistently use state name “TRANSMIT” instead of “SEND”
- Add/change figures in RSDPxSP and RSDPxCPL chapters
- Refer to “IDCODE or BYPASS” register in escape sequence
- Fix small grammar errors
- Improve wording (remove “we” language, split long sentences)

### [0.1.2] - 2026-07-27
- Change rules governing RD-PAYLOAD of DMI transations
- Add clarification section on how to handle DMI errors
- Define "zero hold-time requirement", "launch", "latch"
- Change reading order in transaction format (now left-to-right)
- Clarify references to the RISC-V Debug Specification
- Rename CLOCK/DATA -> RCLK/RDAT
- Add suggested debug connectors (same as for JTAG)
- Rework RSDPxSP and RSDPxCPL

### [0.1.1] - 2026-05-08
- Fix link to Debug Spec in bibliography
- Fix link to reference implementation repository
- Fix converter name in diagram
- Make RSDPxSP diagram look consistent with RSDPxCPL diagram

### [0.1.0] - 2026-05-07
- Initial release
