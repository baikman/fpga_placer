from math import exp
from pathlib import Path

# The annealer calculates index = floor(64 * positive_delta / temperature).
# Ratios >= 16 are rejected: their probability is below 16-bit resolution.
thresholds = [
    min(65535, int(65536 * exp(-index / 64.0)))
    for index in range(1024)
]

Path(__file__).with_name("acceptance.hex").write_text(
    "".join(f"{threshold:04X}\n" for threshold in thresholds)
)
