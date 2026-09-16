# Hardware bring-up status

Status recorded on 2026-09-17, following review of a user-supplied Basys 3 video dated 2026-09-16. The original Vivado build reports describe the earlier build-time status.

The approximately 40-second recording shows an active Basys 3 with changing LEDs and a seven-segment count that increases during part of the demonstration and remains unchanged during another part. This is consistent with initial operation of the demo. Some controls are obscured by a hand, so the recording does not establish the selected input and expected result for every packet case. It also does not independently identify the loaded bitstream or measure clock frequency, latency or network throughput.

The [original board video](../media/basys3-board-demo.mp4) is included with the project owner's authorization. The following controlled test is **pending**, not a list of measured passing results.

## Acceptance sequence

Use the [programming guide](../boards/basys3/README.md) and its supplied bitstream. Set SW3 down for manual operation, then press BTNU to reset. The display should show `0000`. For each row below, set SW2 SW1 SW0, allow the switches to settle, then press and release BTNC once.

| Switches | Expected outcome | Expected outcome LED | Expected display |
|---|---|---|---|
| 000 | BUY | LD0 | 0001 |
| 001 | HOLD | LD2 | 0001 |
| 010 | SELL | LD1 | 0002 |
| 011 | Unknown symbol | LD3 | 0002 |
| 100 | Wrong UDP port rejected | LD4 | 0002 |
| 101 | Bad checksum rejected | LD4 | 0002 |
| 110 | MAC error rejected | LD4 | 0002 |
| 111 | Truncated packet rejected | LD4 | 0002 |

LD5 should remain off. Record each selected case and its observed result with switches, outcome LEDs and display visible. The display counts BUY/SELL actions in hexadecimal; it does not display stock prices. After manual checks, verify automatic replay using SW3 and reset recovery using BTNU.

This is a 100 MHz internal-packet demonstration. Physical 10G Ethernet integration and the full configurable core's 156.25 MHz timing target remain separate, unfinished milestones.
