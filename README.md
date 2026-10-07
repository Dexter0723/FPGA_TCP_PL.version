# Zynq-7020 FPGA TCP Server

**English** | [繁體中文](README.zh-TW.md)

A synthesizable Gigabit Ethernet TCP server implemented entirely in
Verilog programmable logic on the Xilinx Zynq-7020.

The FPGA connects directly to an Ethernet PHY through RGMII and does not
require the Processing System, Linux, or a software network stack. This
project is intended for high-speed data streaming and hardware network
protocol experiments.

After a TCP connection is established, the example design continuously
transmits incrementing unsigned 8-bit test data from `0x00` to `0xFF`.
Each TCP payload byte represents one data value and does not contain an
additional application header or timestamp.

## Features

- 1 GbE RGMII/GMII data path
- ARP request and reply
- ICMP Echo reply for `ping` testing
- Single-connection TCP server
- Bidirectional TCP application interface
- IPv4 and TCP checksum generation and verification
- Ethernet CRC/FCS generation and verification
- TCP sliding window
- Timeout-based TCP retransmission
- TCP receive buffering
- Clause 22 MDIO PHY initialization and link-status monitoring
- Python tools for data capture and real-time spectrum analysis

## Development Environment

| Item | Configuration |
| --- | --- |
| Development board | ALIENTEK ATK-DF7020P |
| FPGA | AMD/Xilinx Zynq-7020 `XC7Z020CLG400-2` |
| Vivado | 2025.1 |
| Top module | `top` |
| System clock | 50 MHz |
| Ethernet interface | 1 GbE RGMII |

## Default Network Configuration

| Item | Default value |
| --- | --- |
| FPGA MAC address | `00:11:22:33:44:55` |
| FPGA IPv4 address | `192.168.1.10` |
| TCP port | `5000` |
| Recommended PC IPv4 address | `192.168.1.102/24` |

The FPGA MAC address, IPv4 address, and TCP port can be modified in
[`rtl/top.v`](rtl/top.v).

## Quick Start

1. Open [`prj/tcp_zynq7020.xpr`](prj/tcp_zynq7020.xpr) with Vivado 2025.1.
2. Run **Synthesis → Implementation → Generate Bitstream**.
3. Program the FPGA through Vivado Hardware Manager.
4. Configure the PC Ethernet adapter with a static IPv4 address such as
   `192.168.1.102/24`.
5. Connect the FPGA board to the PC with an Ethernet cable.
6. Verify the connection by running:

```powershell
ping 192.168.1.10
```

A successful reply confirms that the RGMII interface, PHY, ARP, IPv4,
and ICMP paths are operating.

## FPGA Application Interface

[`rtl/top.v`](rtl/top.v) connects the PHY, RGMII interface, and TCP
core. User logic communicates with
[`eth_tcp_top`](rtl/eth_tcp_top.v) through the application interface:

```text
User logic / ADC
        ⇅
  app_tx / app_rx
        ⇅
   eth_tcp_top
        ⇅
       GMII
        ⇅
       RGMII
        ⇅
  Ethernet PHY
```

### Interface Signals

| Signal | Description |
| --- | --- |
| `tcp_app_clk` | Application-interface clock, currently 125 MHz |
| `tcp_connected_o` | High when the TCP connection is established |
| `app_tx_data[7:0]` | Data transmitted from the FPGA to the PC |
| `app_tx_valid` | Indicates that `app_tx_data` is valid |
| `app_tx_ready` | Indicates that the TCP core can accept TX data |
| `app_tx_flush` | Immediately sends the current payload before it reaches the MSS |
| `app_rx_data[7:0]` | Data received by the FPGA from the PC |
| `app_rx_valid` | Indicates that `app_rx_data` is valid |
| `app_rx_ready` | Indicates that user logic can accept RX data |
| `app_rx_last` | Indicates the final byte of the current TCP payload |

## Transmitting Data from the FPGA

The TCP core accepts one byte only when both `app_tx_valid` and
`app_tx_ready` are high on a rising edge of `tcp_app_clk`.

If `app_tx_ready` is low, user logic must keep `app_tx_data` and
`app_tx_valid` unchanged until the transfer is accepted.

The following simplified example continuously generates incrementing
8-bit test data:

```verilog
reg [7:0] tx_data;

assign app_tx_valid = tcp_connected_o;
assign app_tx_flush = 1'b0;

always @(posedge tcp_app_clk or negedge sys_rst_n) begin
    if (!sys_rst_n || !tcp_connected_o)
        tx_data <= 8'd0;
    else if (app_tx_valid && app_tx_ready)
        tx_data <= tx_data + 8'd1;
end
```

For continuous streaming, `app_tx_flush` can remain low. The TCP core
automatically transmits the payload after it reaches the configured MSS.

To transmit a short payload before it reaches the MSS, assert
`app_tx_flush` during the same clock cycle in which the final byte is
accepted with `app_tx_valid && app_tx_ready`.

## Receiving Data on the FPGA

The following simplified example keeps the receive interface ready and
stores each byte received from the PC:

```verilog
assign app_rx_ready = 1'b1;

always @(posedge tcp_app_clk) begin
    if (app_rx_valid && app_rx_ready) begin
        command <= app_rx_data;

        if (app_rx_last)
            packet_done <= 1'b1;
    end
end
```

If the user logic cannot temporarily accept more data, it may drive
`app_rx_ready` low. The TCP core will hold `app_rx_data`,
`app_rx_valid`, and `app_rx_last` until the byte is accepted.

The current `top` module recognizes the following command bytes from the
PC:

| Command | Intended operation |
| --- | --- |
| `0x01` | Start transmission |
| `0x00` | Stop transmission |

The command state is currently recorded, but the TX path remains
directly controlled by the TCP connection state. Therefore, the example
continues transmitting test data after the connection is established.
The start and stop commands do not yet pause or resume the TX stream.

## Connecting an ADC or Another Data Source

To replace the incrementing test data with ADC samples or another data
source:

1. Remove or replace `test_counter` in [`rtl/top.v`](rtl/top.v).
2. Connect the source data to `app_tx_data`.
3. Assert `app_tx_valid` whenever valid source data is available.
4. Advance to the next source byte only when
   `app_tx_valid && app_tx_ready` is true.
5. If the source uses a different clock domain, insert an asynchronous
   FIFO for clock-domain crossing.
6. Use `tcp_connected_o` to stop or clear the data path when no TCP
   connection is active.

The application interface is 8 bits wide. Multi-byte ADC samples must
therefore be serialized into bytes in a defined byte order. The PC
software must reconstruct the samples using the same format.

## Python Tools

Python 3.11 is recommended. The project was tested with Python 3.11.9.

Install the required third-party packages with:

```powershell
python -m pip install numpy matplotlib pandas
```

| Program | Description |
| --- | --- |
| [`Realtime_ADC_Monitor.py`](python/Realtime_ADC_Monitor.py) | Displays the 8-bit data stream, TCP throughput, time-domain waveform, and NumPy `rFFT` spectrum in real time without writing files |
| [`Catch_8bit.py`](python/Catch_8bit.py) | Receives a specified amount of data, verifies the incrementing test pattern, and optionally exports BIN and CSV files |
| [`CSV_show.py`](python/CSV_show.py) | Loads an existing CSV file and displays its time-domain waveform and NumPy `rFFT` spectrum |

### Real-Time Monitoring

```powershell
python python/Realtime_ADC_Monitor.py
```

### Fixed-Length Data Capture

```powershell
python python/Catch_8bit.py
```

### CSV Analysis

```powershell
python python/CSV_show.py
```

`Realtime_ADC_Monitor.py` currently uses a default sampling rate of
125 MS/s for the frequency axis.

`CSV_show.py` currently uses a default sampling rate of 25 MS/s and
marks an expected 500 kHz input signal. Update the corresponding
sampling-rate setting when using a different ADC configuration.

## Demo

![Zynq-7020 FPGA TCP server demo](docs\realtime.gif)

## Project Structure

```text
zynq7020-fpga-tcp-server/
├─ prj/       Vivado project
├─ rtl/       ARP, ICMP, TCP, MDIO, and RGMII RTL
├─ sim/       Testbenches for the top module, TCP, MDIO, and other modules
├─ python/    PC-side data capture and real-time analysis tools
├─ xdc/       Pin assignments and timing constraints
├─ README.md
├─ README.zh-TW.md
└─ LICENSE
```

## Known Limitations

- The design uses a static IPv4 configuration.
- Only one TCP connection is supported.
- DHCP and IPv6 are not supported.
- A complete TCP congestion-control implementation is not included.
- The default top module transmits incrementing test data instead of
  actual ADC samples.
- The XDC pin assignments are specific to the ALIENTEK ATK-DF7020P
  development board.
- Operation on other boards or PHY devices may require changes to the
  pin constraints, clocking, reset timing, and MDIO initialization.

## License

This project is licensed under the [MIT License](LICENSE).

The pin constraints are based on the ALIENTEK ATK-DF7020P board
documentation. ALIENTEK is a trademark of its respective owner.