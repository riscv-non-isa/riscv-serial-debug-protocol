# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This changelog only concerns changes visible in the specification PDF.
Any changes to the CI, READMEs or reference implementation are not mentioned here.

Due to the limited version space with the new non-semantic version scheme imposed by the new template, we will avoid doing numbered releases except for the officially-mandated milestones.
Instead, interim releases will be identified by their commit hash and date, and the PDFs will be preserved for easy access in a separate branch of this repository.

## [Unreleased]

## [0.0-ccbf69c] - 2026-11-16
[spec-rsdp-v0.0-ccbf69c-20261116.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/spec-rsdp-v0.0-ccbf69c-20261116.pdf)
- Change to newly forked template
- Fix references to a "DMI-internal bus"
- Remove references to deprecated `DTMCS_RD` and `DTMCS_WR` transaction types
- Fix some typos and improve wording
- Define that a `DMI_*_SA` transaction after an `ENABLE` sequence is undefined
- Make it clear that read data is also sent on DMI errors
- Update reference implementation  port description
- Add clarification that the NOP transaction serves little use in FAST state

## Releases on old gitlab repository

Prior to moving to github and a new version of the template, this project was maintained in the [riscv-rsdp-spec repository on gitlab](https://gitlab.com/lauterbach/riscv-rsdp-spec).
Releases below are versioned using the old semantic versioning scheme.

### [0.1.5] - 2026-10-20
[gitlab/spec-rsdp-v0.1.5.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/gitlab/spec-rsdp-v0.1.5.pdf)
- Clarify idle cycles between transactions

### [0.1.4] - 2026-10-20
[gitlab/spec-rsdp-v0.1.4.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/gitlab/spec-rsdp-v0.1.4.pdf)
- Clarify escape sequence encoding
- Remove TRN fields where neither side drives in order to not depend on pull resistors
- Define how extensions can use DMI-internal bus addresses and TT encodings

### [0.1.3] - 2026-08-25
[gitlab/spec-rsdp-v0.1.3.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/gitlab/spec-rsdp-v0.1.3.pdf)
- Add rationale behind arbitrary time constants in RSDPxSP
- In RSDPxSP, consistently use state name “TRANSMIT” instead of “SEND”
- Add/change figures in RSDPxSP and RSDPxCPL chapters
- Refer to “IDCODE or BYPASS” register in escape sequence
- Fix small grammar errors
- Improve wording (remove “we” language, split long sentences)

### [0.1.2] - 2026-07-27
[gitlab/spec-rsdp-v0.1.2.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/gitlab/spec-rsdp-v0.1.2.pdf)
- Change rules governing RD-PAYLOAD of DMI transations
- Add clarification section on how to handle DMI errors
- Define "zero hold-time requirement", "launch", "latch"
- Change reading order in transaction format (now left-to-right)
- Clarify references to the RISC-V Debug Specification
- Rename CLOCK/DATA -> RCLK/RDAT
- Add suggested debug connectors (same as for JTAG)
- Rework RSDPxSP and RSDPxCPL

### [0.1.1] - 2026-05-08
[gitlab/spec-rsdp-v0.1.1.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/gitlab/spec-rsdp-v0.1.1.pdf)
- Fix link to Debug Spec in bibliography
- Fix link to reference implementation repository
- Fix converter name in diagram
- Make RSDPxSP diagram look consistent with RSDPxCPL diagram

### [0.1.0] - 2026-05-07
[gitlab/spec-rsdp-v0.1.0.pdf](https://github.com/riscv-non-isa/riscv-serial-debug-protocol/blob/pdfs/gitlab/spec-rsdp-v0.1.0.pdf)
- Initial release
