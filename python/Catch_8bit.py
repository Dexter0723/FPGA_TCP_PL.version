from pathlib import Path
from datetime import datetime
import socket
import time


# ===================== Settings =====================
TCP_IP = "192.168.1.10"
TCP_PORT = 5000

BD_BYTES = 64 * 1024
SOCKET_TIMEOUT_SECONDS = 120
EXPECTED_BYTES = 8000

SAVE_FOLDER = Path(r"python\Data")

VERIFY_PATTERN = False
MAKE_CSV = True

# PC -> FPGA command
CMD_START = 0x01
CMD_STOP = 0x00

# Used only to reject physically impossible timing results.
LINK_SPEED_BPS = 1_000_000_000
# ====================================================


def send_command(
    sock: socket.socket,
    command: int,
    command_name: str,
) -> None:
    """Send exactly one binary command byte to the FPGA."""

    if not 0 <= command <= 0xFF:
        raise ValueError("Command must be between 0x00 and 0xFF.")

    sock.sendall(bytes([command]))

    print(
        f"Sent command: {command_name} "
        f"(0x{command:02X})"
    )


def verify_pattern(
    data: bytes | bytearray,
    start_index: int,
) -> tuple[bool, int]:
    for offset, value in enumerate(data):
        expected = (start_index + offset) & 0xFF

        if value != expected:
            return False, start_index + offset

    return True, -1


def make_csv(bin_path: Path, csv_path: Path) -> None:
    sample_index = 0

    print(f"Creating CSV: {csv_path}")

    with bin_path.open("rb") as src, csv_path.open(
        "w",
        encoding="utf-8",
        newline="",
    ) as dst:
        dst.write("Index,ADC_Value\n")

        while True:
            block = src.read(1024 * 1024)

            if not block:
                break

            lines = []

            for value in block:
                lines.append(f"{sample_index},{value}\n")
                sample_index += 1

            dst.write("".join(lines))


def mib_per_second(byte_count: int, seconds: float) -> float:
    return byte_count / seconds / (1024 * 1024)


def mbits_per_second(byte_count: int, seconds: float) -> float:
    return byte_count * 8 / seconds / 1_000_000


def main() -> None:
    overall_start_time = time.perf_counter()

    SAVE_FOLDER.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = f"TCP_Data_{timestamp}"

    part_path = SAVE_FOLDER / f"{base_name}.bin.part"
    bin_path = SAVE_FOLDER / f"{base_name}.bin"
    csv_path = SAVE_FOLDER / f"{base_name}.csv"

    payload = bytearray(EXPECTED_BYTES)
    payload_view = memoryview(payload)

    received = 0
    pattern_ok = True
    connected = False

    socket_open_start_time: float | None = None
    socket_open_end_time: float | None = None
    connect_start_time: float | None = None
    connected_time: float | None = None
    first_data_time: float | None = None
    last_data_time: float | None = None

    print(f"Connecting to FPGA: {TCP_IP}:{TCP_PORT}")

    try:
        socket_open_start_time = time.perf_counter()

        sock = socket.socket(
            socket.AF_INET,
            socket.SOCK_STREAM,
        )

        sock.settimeout(SOCKET_TIMEOUT_SECONDS)

        # Send small control commands immediately.
        sock.setsockopt(
            socket.IPPROTO_TCP,
            socket.TCP_NODELAY,
            1,
        )

        socket_open_end_time = time.perf_counter()

        # Create the file before connect(), so file creation time is not
        # included in the TCP transfer timing.
        with sock, part_path.open("wb") as output:
            connect_start_time = time.perf_counter()

            sock.connect((TCP_IP, TCP_PORT))

            connected_time = time.perf_counter()
            connected = True

            print("Connected successfully.")

            try:
                # PC -> FPGA: start command
                send_command(
                    sock,
                    CMD_START,
                    "START",
                )

                print(
                    f"Receiving {EXPECTED_BYTES:,} bytes..."
                )

                while received < EXPECTED_BYTES:
                    remaining = EXPECTED_BYTES - received

                    # Receive one byte first to obtain a meaningful
                    # first-byte timestamp.
                    if first_data_time is None:
                        request_size = 1
                    else:
                        request_size = min(
                            BD_BYTES,
                            remaining,
                        )

                    count = sock.recv_into(
                        payload_view[
                            received : received + request_size
                        ],
                        request_size,
                    )

                    arrival_time = time.perf_counter()

                    if count == 0:
                        raise ConnectionError(
                            "TCP connection closed early. "
                            f"Received {received:,} of "
                            f"{EXPECTED_BYTES:,} bytes."
                        )

                    if first_data_time is None:
                        first_data_time = arrival_time

                    received += count

                    if received == EXPECTED_BYTES:
                        last_data_time = arrival_time

                print(
                    f"Received: {received:,}/"
                    f"{EXPECTED_BYTES:,} bytes"
                )

            finally:
                # PC -> FPGA: stop command
                #
                # This executes even if receiving raises an error,
                # as long as the TCP connection is still usable.
                if connected:
                    try:
                        send_command(
                            sock,
                            CMD_STOP,
                            "STOP",
                        )

                        # Give the command a short time to reach the FPGA
                        # before closing the socket.
                        time.sleep(0.05)

                    except OSError as command_error:
                        print(
                            "Could not send STOP command: "
                            f"{command_error}"
                        )

            # File I/O remains outside the measured receive interval.
            output.write(payload[:received])

        if received != EXPECTED_BYTES:
            raise RuntimeError(
                f"Expected {EXPECTED_BYTES:,} bytes, "
                f"but received {received:,} bytes."
            )

        if (
            socket_open_start_time is None
            or socket_open_end_time is None
            or connect_start_time is None
            or connected_time is None
            or first_data_time is None
            or last_data_time is None
        ):
            raise RuntimeError(
                "TCP timing information is incomplete."
            )

        if VERIFY_PATTERN:
            pattern_ok, bad_index = verify_pattern(
                payload,
                0,
            )

            if not pattern_ok:
                actual = payload[bad_index]
                expected = bad_index & 0xFF

                raise ValueError(
                    f"Data mismatch at byte {bad_index:,}: "
                    f"got 0x{actual:02X}, "
                    f"expected 0x{expected:02X}"
                )

        socket_open_time = (
            socket_open_end_time - socket_open_start_time
        )

        tcp_connect_time = (
            connected_time - connect_start_time
        )

        connect_to_first_time = (
            first_data_time - connected_time
        )

        tcp_active_time = (
            last_data_time - first_data_time
        )

        connect_to_complete_time = (
            last_data_time - connected_time
        )

        total_receive_time = (
            last_data_time - overall_start_time
        )

        active_bytes = max(received - 1, 0)

        minimum_active_time = (
            active_bytes * 8 / LINK_SPEED_BPS
        )

        effective_speed_mib = mib_per_second(
            received,
            connect_to_complete_time,
        )

        effective_speed_mbps = mbits_per_second(
            received,
            connect_to_complete_time,
        )

        part_path.replace(bin_path)

        print("\nReceive complete.")
        print(
            f"Bytes                         : "
            f"{received:,}"
        )
        print(
            f"Pattern check                 : "
            f"{'OK' if VERIFY_PATTERN and pattern_ok else 'Disabled'}"
        )
        print(
            f"Socket create/config time     : "
            f"{socket_open_time:.6f} s"
        )
        print(
            f"TCP connect time              : "
            f"{tcp_connect_time:.6f} s"
        )
        print(
            f"Connect -> first byte         : "
            f"{connect_to_first_time:.6f} s"
        )
        print(
            f"First byte -> last byte       : "
            f"{tcp_active_time:.6ff} s"
        )
        print(
            f"Connect -> complete           : "
            f"{connect_to_complete_time:.6f} s"
        )
        print(
            f"Total receive time            : "
            f"{total_receive_time:.6f} s"
        )
        print(
            f"Effective speed               : "
            f"{effective_speed_mib:.2f} MiB/s"
        )
        print(
            f"Effective speed               : "
            f"{effective_speed_mbps:.2f} Mb/s"
        )

        if (
            tcp_active_time > 0.0
            and tcp_active_time >= minimum_active_time
        ):
            active_speed_mib = mib_per_second(
                active_bytes,
                tcp_active_time,
            )

            active_speed_mbps = mbits_per_second(
                active_bytes,
                tcp_active_time,
            )

            print(
                f"TCP active speed              : "
                f"{active_speed_mib:.2ff} MiB/s"
            )
            print(
                f"TCP active speedfig speed              : "
                f"{active_speed_mbps:.2f} Mb/s"
            )
        else:
            print(
                "TCP active speed              : N/A "
                "(payload was socket-buffered)"
            )

        if MAKE_CSV:
            make_csv(bin_path, csv_path)
            bin_path.unlink()

            print(
                f"CSV file                      : "
                f"{csv_path}"
            )
            print("Temporary .bin file deleted.")
        else:
            print(
                f"Binary file                   : "
                f"{bin_path}"
            )

    except Exception as error:
        # Preserve bytes that were already received if an error occurred.
        if received > 0:
            try:
                part_path.write_bytes(payload[:received])
            except OSError as save_error:
                print(
                    "Could not save partial data: "
                    f"{save_error}"
                )

        print(f"\nERROR: {error}")
        print(
            f"Partial bytes received: "
            f"{received:,}"
        )
        print(f"Partial file: {part_path}")


if __name__ == "__main__":
    main()