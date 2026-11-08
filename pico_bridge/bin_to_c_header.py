from pathlib import Path

data = Path("test3.bin").read_bytes()
values = ", ".join(f"0x{b:02X}" for b in data)

Path("netlist_data.h").write_text(
    "#pragma once\n#include <stdint.h>\n"
    "static const uint8_t netlist_data[] = {" + values + "};\n"
)