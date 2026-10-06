from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


CSV_PATH = Path(r"python\Data\test_data.csv")

SAMPLE_RATE_HZ = 25_000_000
EXPECTED_TONE_HZ = 500_000

# ADC 資料格式：unsigned 8-bit，範圍 0～255
ADC_MIDPOINT = 128.0

ADC_REFERENCE_RMS_V = 0.700
EXTERNAL_GAIN = 2.0 * 2.0

VOLT_PER_COUNT = (
    ADC_REFERENCE_RMS_V
    / (ADC_MIDPOINT * np.sqrt(2.0))
    * EXTERNAL_GAIN
)


def calculate_single_sided_fft(
    signal: np.ndarray,
    sample_rate_hz: float,
) -> tuple[np.ndarray, np.ndarray]:
    """計算加上 Hann window 的單邊振幅頻譜。"""

    sample_count = len(signal)

    # 去除 DC
    signal = signal - np.mean(signal)

    window = np.hanning(sample_count)
    windowed_signal = signal * window

    spectrum = np.fft.rfft(windowed_signal)
    frequencies_hz = np.fft.rfftfreq(
        sample_count,
        d=1.0 / sample_rate_hz,
    )

    # 使用 window coherent gain 校正振幅
    amplitude = np.abs(spectrum) / np.sum(window)

    # 單邊頻譜除了 DC 與 Nyquist 外都要乘以 2
    if sample_count % 2 == 0:
        amplitude[1:-1] *= 2.0
    else:
        amplitude[1:] *= 2.0

    return frequencies_hz, amplitude


def main() -> None:
    df = pd.read_csv(CSV_PATH)

    required_columns = {"Index", "ADC_Value"}

    if not required_columns.issubset(df.columns):
        raise ValueError(
            "CSV 必須包含 Index 與 ADC_Value 欄位"
        )

    index = df["Index"].to_numpy(dtype=np.int64)
    raw_samples = df["ADC_Value"].to_numpy(dtype=np.int64)

    if len(raw_samples) < 2:
        raise ValueError("資料點不足")

    if np.isnan(df["ADC_Value"]).any():
        raise ValueError("ADC_Value 包含空白或無效資料")

    # unsigned 8-bit 合法範圍
    if raw_samples.min() < 0 or raw_samples.max() > 255:
        raise ValueError(
            "ADC 資料超出 unsigned 8-bit 範圍 0～255"
        )

    # 將 unsigned 8-bit 轉成以 0 為中心的 ADC counts
    centered_samples = (
        raw_samples.astype(np.float64) - ADC_MIDPOINT
    )

    voltage = centered_samples * VOLT_PER_COUNT

    time_us = (
        (index - index[0])
        / SAMPLE_RATE_HZ
        * 1_000_000.0
    )

    frequencies_hz, amplitude = calculate_single_sided_fft(
        centered_samples,
        SAMPLE_RATE_HZ,
    )

    # 略過 DC，尋找最大頻率成分
    peak_index = int(np.argmax(amplitude[1:])) + 1
    peak_frequency_hz = frequencies_hz[peak_index]
    peak_amplitude = amplitude[peak_index]

    duration_us = (
        len(raw_samples)
        / SAMPLE_RATE_HZ
        * 1_000_000.0
    )

    frequency_resolution_hz = (
        SAMPLE_RATE_HZ / len(raw_samples)
    )

    print("===== ADC Result =====")
    print(f"Samples:                 {len(raw_samples)}")
    print(f"Duration:                {duration_us:.3f} us")
    print(
        f"Frequency resolution:    "
        f"{frequency_resolution_hz:.3f} Hz"
    )

    print("\n----- Raw unsigned 8-bit -----")
    print(f"Minimum:                 {raw_samples.min()}")
    print(f"Maximum:                 {raw_samples.max()}")
    print(
        f"Peak-to-peak:            "
        f"{np.ptp(raw_samples)} counts"
    )
    print(
        f"Mean:                    "
        f"{np.mean(raw_samples):.3f} counts"
    )

    print("\n----- Centered ADC counts -----")
    print(f"Minimum:                 {centered_samples.min():.3f}")
    print(f"Maximum:                 {centered_samples.max():.3f}")
    print(
        f"Peak-to-peak:            "
        f"{np.ptp(centered_samples):.3f} counts"
    )
    print(f"Mean:                    {np.mean(centered_samples):.3f}")

    print("\n----- Voltage -----")
    print(f"Minimum:                 {voltage.min():.6f} V")
    print(f"Maximum:                 {voltage.max():.6f} V")
    print(
        f"Peak-to-peak:            "
        f"{np.ptp(voltage):.6f} V"
    )
    print(f"Mean:                    {np.mean(voltage):.6f} V")

    print("\n----- FFT -----")
    print(
        f"Detected frequency:      "
        f"{peak_frequency_hz / 1_000_000:.6f} MHz"
    )
    print(
        f"Detected amplitude:      "
        f"{peak_amplitude:.3f} counts"
    )
    print(
        f"Expected frequency:      "
        f"{EXPECTED_TONE_HZ / 1_000_000:.6f} MHz"
    )

    fig, (ax_time, ax_fft) = plt.subplots(
        2,
        1,
        figsize=(14, 8),
    )

    ax_time.plot(
        time_us,
        voltage,
        color="green",
        linewidth=1.0,
    )

    ax_time.set_title("ADC time-domain waveform")
    ax_time.set_xlabel("Time (us)")
    ax_time.set_ylabel("Voltage (V)")
    ax_time.grid(True, linestyle="--", alpha=0.5)

    ax_fft.plot(
        frequencies_hz / 1_000_000.0,
        amplitude,
        color="blue",
        linewidth=1.0,
    )

    ax_fft.axvline(
        EXPECTED_TONE_HZ / 1_000_000.0,
        color="red",
        linestyle="--",
        label=(
            f"Expected "
            f"{EXPECTED_TONE_HZ / 1_000_000:.3f} MHz"
        ),
    )

    ax_fft.set_xlim(
        0,
        SAMPLE_RATE_HZ / 2.0 / 1_000_000.0,
    )

    ax_fft.set_title(
        f"FFT peak: "
        f"{peak_frequency_hz / 1_000_000:.6f} MHz"
    )
    ax_fft.set_xlabel("Frequency (MHz)")
    ax_fft.set_ylabel("Amplitude (ADC counts)")
    ax_fft.grid(True, linestyle="--", alpha=0.5)
    ax_fft.legend()

    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()