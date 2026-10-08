from __future__ import annotations

import collections
import socket
import threading
import time
from dataclasses import dataclass

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.animation import FuncAnimation
from matplotlib.widgets import Button


@dataclass(frozen=True)
class MonitorConfig:
    """Runtime settings for the TCP ADC monitor."""

    tcp_ip: str = "192.168.1.10"
    tcp_port: int = 5000

    sample_rate_hz: float = 25_000_000.0
    display_points: int = 2_000
    plot_buffer_size: int = 10_000

    receive_buffer_bytes: int = 1024 * 1024
    receive_queue_chunks: int = 64
    socket_receive_buffer_bytes: int = 32 * 1024 * 1024

    animation_interval_ms: int = 30
    fft_update_interval_s: float = 0.2


class SpectrumAnalyzer:
    """NumPy-based, one-sided spectrum analyzer for unsigned 8-bit ADC data."""

    ADC_FULL_SCALE_PEAK = 127.5
    MINIMUM_DBFS = -120.0

    def __init__(self, sample_count: int, sample_rate_hz: float) -> None:
        self.sample_count = sample_count
        self.sample_rate_hz = sample_rate_hz

        self.window = np.hanning(sample_count).astype(np.float32)
        self.window_gain = float(np.sum(self.window))
        self.frequency_mhz = (
            np.fft.rfftfreq(sample_count, d=1.0 / sample_rate_hz) / 1_000_000.0
        )

    def calculate(self, samples: np.ndarray) -> tuple[np.ndarray, float]:
        """Return spectrum in dBFS and the strongest non-DC frequency in MHz."""

        centered = samples.astype(np.float32) - np.mean(samples, dtype=np.float64)
        spectrum = np.fft.rfft(centered * self.window)

        amplitude = 2.0 * np.abs(spectrum) / self.window_gain
        amplitude[0] *= 0.5

        normalized = amplitude / self.ADC_FULL_SCALE_PEAK
        magnitude_dbfs = 20.0 * np.log10(np.maximum(normalized, 1.0e-6))
        magnitude_dbfs = np.maximum(magnitude_dbfs, self.MINIMUM_DBFS)

        if magnitude_dbfs.size > 1:
            peak_index = int(np.argmax(magnitude_dbfs[1:])) + 1
        else:
            peak_index = 0

        return magnitude_dbfs, float(self.frequency_mhz[peak_index])


class TcpReceiver:
    """Receive TCP data and calculate network throughput."""

    def __init__(self, config: MonitorConfig) -> None:
        self.config = config
        self.socket: socket.socket | None = None

        self.stop_event = threading.Event()
        self.connected_event = threading.Event()

        self.chunk_lock = threading.Lock()
        self.chunks: collections.deque[bytes] = collections.deque(
            maxlen=config.receive_queue_chunks
        )

        self.stats_lock = threading.Lock()
        self.interval_bytes = 0
        self.current_mbps = 0.0

        self.error_lock = threading.Lock()
        self.last_error = ""

        self.worker_threads: list[threading.Thread] = []

    def connect(self) -> None:
        tcp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        tcp_socket.setsockopt(
            socket.SOL_SOCKET,
            socket.SO_RCVBUF,
            self.config.socket_receive_buffer_bytes,
        )
        tcp_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        tcp_socket.settimeout(10.0)

        print(
            f"Connecting to FPGA "
            f"{self.config.tcp_ip}:{self.config.tcp_port}..."
        )
        tcp_socket.connect((self.config.tcp_ip, self.config.tcp_port))
        tcp_socket.settimeout(None)

        self.socket = tcp_socket
        self.connected_event.set()
        print("Connected. Receiving ADC data...")

        self.worker_threads = [
            threading.Thread(
                target=self._receive_worker,
                name="tcp-receiver",
                daemon=True,
            ),
            threading.Thread(
                target=self._speed_worker,
                name="throughput-calculator",
                daemon=True,
            ),
        ]

        for worker in self.worker_threads:
            worker.start()

    @property
    def connected(self) -> bool:
        return self.connected_event.is_set()

    def get_throughput_mbps(self) -> float:
        with self.stats_lock:
            return self.current_mbps

    def get_last_error(self) -> str:
        with self.error_lock:
            return self.last_error

    def drain_chunks(self) -> list[bytes]:
        with self.chunk_lock:
            pending = list(self.chunks)
            self.chunks.clear()
        return pending

    def close(self) -> None:
        if self.stop_event.is_set():
            return

        self.stop_event.set()
        self.connected_event.clear()

        if self.socket is not None:
            try:
                self.socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.socket.close()
            self.socket = None

        for worker in self.worker_threads:
            worker.join(timeout=1.0)

    def _receive_worker(self) -> None:
        if self.socket is None:
            return

        receive_buffer = bytearray(self.config.receive_buffer_bytes)
        buffer_view = memoryview(receive_buffer)

        try:
            while not self.stop_event.is_set():
                received = self.socket.recv_into(buffer_view)
                if received == 0:
                    self._set_error("FPGA closed the TCP connection")
                    break

                with self.stats_lock:
                    self.interval_bytes += received

                display_chunk = bytes(buffer_view[:received])
                with self.chunk_lock:
                    self.chunks.append(display_chunk)

        except OSError as error:
            if not self.stop_event.is_set():
                self._set_error(f"TCP receive error: {error}")
        finally:
            self.connected_event.clear()

    def _speed_worker(self) -> None:
        previous_time = time.monotonic()

        while not self.stop_event.wait(1.0):
            current_time = time.monotonic()
            elapsed = current_time - previous_time
            previous_time = current_time

            with self.stats_lock:
                byte_count = self.interval_bytes
                self.interval_bytes = 0
                self.current_mbps = byte_count * 8.0 / elapsed / 1_000_000.0

    def _set_error(self, message: str) -> None:
        with self.error_lock:
            self.last_error = message
        print(f"\n[Connection] {message}")

class AdcMonitor:
    """Matplotlib user interface for live time- and frequency-domain plots."""

    def __init__(self, config: MonitorConfig, receiver: TcpReceiver) -> None:
        self.config = config
        self.receiver = receiver

        self.adc_buffer = np.full(
            config.plot_buffer_size,
            128,
            dtype=np.uint8,
        )
        self.time_axis = np.arange(config.plot_buffer_size)
        self.time_width = config.display_points

        self.is_paused = False
        self.last_fft_update = 0.0
        self.peak_frequency_mhz = 0.0

        self.spectrum = SpectrumAnalyzer(
            sample_count=config.plot_buffer_size,
            sample_rate_hz=config.sample_rate_hz,
        )

        self.figure, (self.time_axes, self.frequency_axes) = plt.subplots(
            2,
            1,
            figsize=(14, 7.5),
        )
        self._configure_window()
        self._configure_plots()
        self._configure_controls()

        self.animation = FuncAnimation(
            self.figure,
            self._update,
            interval=config.animation_interval_ms,
            blit=False,
            cache_frame_data=False,
        )

    def show(self) -> None:
        plt.show()

    def _configure_window(self) -> None:
        manager = self.figure.canvas.manager
        manager.set_window_title("FPGA ADC TCP Monitor")

        window = getattr(manager, "window", None)
        if window is not None:
            if hasattr(window, "wm_geometry"):
                window.wm_geometry("+10+10")
            elif hasattr(window, "geometry"):
                window.geometry("+10+10")

    def _configure_plots(self) -> None:
        (self.time_line,) = self.time_axes.plot(
            self.time_axis,
            self.adc_buffer,
            color="#2E8B57",
            linewidth=1.2,
        )
        self.time_axes.set_xlim(
            self.config.plot_buffer_size - self.time_width,
            self.config.plot_buffer_size,
        )
        self.time_axes.set_ylim(-5, 260)
        self.time_axes.set_title("Time Domain")
        self.time_axes.set_ylabel("ADC value")
        self.time_axes.grid(True, linestyle="--", alpha=0.4)

        initial_spectrum = np.full(
            self.spectrum.frequency_mhz.size,
            SpectrumAnalyzer.MINIMUM_DBFS,
        )
        (self.frequency_line,) = self.frequency_axes.plot(
            self.spectrum.frequency_mhz,
            initial_spectrum,
            color="#2864DC",
            linewidth=1.2,
        )
        self.frequency_axes.set_xlim(0.0, self.config.sample_rate_hz / 2e6)
        self.frequency_axes.set_ylim(-120.0, 0.0)
        self.frequency_axes.set_title("Frequency Domain (NumPy rFFT)")
        self.frequency_axes.set_xlabel("Frequency (MHz)")
        self.frequency_axes.set_ylabel("Magnitude (dBFS)")
        self.frequency_axes.grid(True, linestyle="--", alpha=0.4)

        self.figure.subplots_adjust(top=0.87, bottom=0.15, hspace=0.38)

    def _configure_controls(self) -> None:
        pause_axes = self.figure.add_axes([0.435, 0.035, 0.13, 0.045])

        self.pause_button = Button(
            pause_axes,
            "Pause",
            color="#EAEAEA",
            hovercolor="#D0D0D0",
        )
        self.pause_button.on_clicked(self._toggle_pause)

        self.figure.canvas.mpl_connect("scroll_event", self._on_scroll)
        self.figure.canvas.mpl_connect("close_event", self._on_close)

        self.figure.text(
            0.5,
            0.01,
            "Mouse wheel: zoom  |  Shift + wheel over FFT: magnitude scale",
            ha="center",
            fontsize=9,
            color="#555555",
        )

    def _toggle_pause(self, _event=None) -> None:
        self.is_paused = not self.is_paused
        self.pause_button.label.set_text("Resume" if self.is_paused else "Pause")
        self.pause_button.ax.set_facecolor(
            "#FFD6D6" if self.is_paused else "#EAEAEA"
        )
        self.figure.canvas.draw_idle()

    def _on_scroll(self, event) -> None:
        if event.inaxes is None:
            return

        scale = 0.8 if event.button == "up" else 1.25

        if event.inaxes == self.time_axes:
            self.time_width = int(self.time_width * scale)
            self.time_width = max(
                50,
                min(self.config.plot_buffer_size, self.time_width),
            )
            self.time_axes.set_xlim(
                self.config.plot_buffer_size - self.time_width,
                self.config.plot_buffer_size,
            )

        elif event.inaxes == self.frequency_axes:
            if event.key == "shift":
                lower, upper = self.frequency_axes.get_ylim()
                new_height = max(10.0, min(160.0, (upper - lower) * scale))
                self.frequency_axes.set_ylim(-new_height, 0.0)
            else:
                lower, upper = self.frequency_axes.get_xlim()
                center = event.xdata if event.xdata is not None else (lower + upper) / 2
                nyquist_mhz = self.config.sample_rate_hz / 2e6
                new_lower = max(0.0, center - (center - lower) * scale)
                new_upper = min(
                    nyquist_mhz,
                    center + (upper - center) * scale,
                )

                if new_upper - new_lower >= 0.1:
                    self.frequency_axes.set_xlim(new_lower, new_upper)

        self.figure.canvas.draw_idle()

    def _on_close(self, _event) -> None:
        self.receiver.close()

    def _update(self, _frame):
        if not self.is_paused:
            self._consume_received_data()

        self._update_title()
        return self.time_line, self.frequency_line

    def _consume_received_data(self) -> None:
        chunks = self.receiver.drain_chunks()
        if not chunks:
            return

        new_samples = np.frombuffer(b"".join(chunks), dtype=np.uint8)
        sample_count = new_samples.size

        if sample_count >= self.config.plot_buffer_size:
            self.adc_buffer[:] = new_samples[-self.config.plot_buffer_size :]
        elif sample_count > 0:
            self.adc_buffer[:-sample_count] = self.adc_buffer[sample_count:]
            self.adc_buffer[-sample_count:] = new_samples

        self.time_line.set_ydata(self.adc_buffer)

        current_time = time.monotonic()
        if current_time - self.last_fft_update >= self.config.fft_update_interval_s:
            self.last_fft_update = current_time
            magnitude_dbfs, peak_frequency_mhz = self.spectrum.calculate(
                self.adc_buffer
            )
            self.frequency_line.set_ydata(magnitude_dbfs)
            self.peak_frequency_mhz = peak_frequency_mhz

    def _update_title(self) -> None:
        if self.is_paused:
            status = "PAUSED"
        elif not self.receiver.connected:
            status = "DISCONNECTED"
        else:
            status = "RUNNING"

        error = self.receiver.get_last_error()
        error_text = f" | {error}" if error else ""

        self.figure.suptitle(
            f"FPGA ADC Monitor — {status}{error_text}\n"
            f"Peak: {self.peak_frequency_mhz:.3f} MHz | "
            f"TCP: {self.receiver.get_throughput_mbps():.2f} Mb/s",
            fontsize=12,
            color="#1F4E8C",
            y=0.98,
        )


def main() -> None:
    config = MonitorConfig()
    receiver = TcpReceiver(config)

    try:
        receiver.connect()
        monitor = AdcMonitor(config, receiver)
        monitor.show()
    except (ConnectionError, OSError) as error:
        print(f"Connection failed: {error}")
    finally:
        receiver.close()


if __name__ == "__main__":
    main()
