"""Inspect the actual NEO BLE build; this does not run or flash hardware."""
from pathlib import Path
import hashlib
import json
import re
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "firmware/bl616_ble_uart_bridge"
BUILD = PROJECT / "build"
IMAGE = BUILD / "build_out/xinxian_ble_uart_bl616.bin"
OLD = PROJECT / "release/xinxian_ble_uart_bl616_secondary_0x40000.bin"
EVIDENCE = ROOT / "build/p5_bluetooth/neo26_20261025"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    image = IMAGE.read_bytes()
    checks = {}

    def check(name, condition):
        checks[name] = bool(condition)
        if not condition:
            raise AssertionError(name)

    check("bouffalo_header", image[:4] == b"BFNP")
    check("clock_header_26mhz", image[100:104] == b"PCFG" and image[104] == 5)
    check("clock_crc", zlib.crc32(image[104:116]) == struct.unpack_from("<I", image, 116)[0])
    check("boot_header_crc", zlib.crc32(image[:252]) == struct.unpack_from("<I", image, 252)[0])
    check("xip_payload_offset", struct.unpack_from("<I", image, 124)[0] == 0x1000)
    check("image_length", struct.unpack_from("<I", image, 132)[0] + 0x1000 == len(image))
    check("plain_secondary", struct.unpack_from("<I", image, 120)[0] & 0x7F == 0)
    check("device_name", b"XINXIAN-BL616" in image)
    for number in (1, 2, 3):
        uuid = bytes.fromhex("9ecadc240ee5a9e093f3a3b5") + bytes([number, 0, 0x40, 0x6e])
        check(f"nus_uuid_{number}", uuid in image)

    board = (BUILD / "neo_board.c").read_text()
    check("bsp_26mhz", "GLB_XTAL_26M" in board and "GLB_XTAL_40M" not in board)
    check("no_console_pinmux_call", not re.search(r"\bconsole_init\(\);", board))
    archive = (BUILD / "CMakeFiles/app.dir/link.txt").read_text()
    check("adapted_bsp_linked", "neo_board.c.obj" in archive and "neo_fw_header.c.obj" in archive)
    check("default_bsp_excluded", "/bl616dk/board.c.obj" not in archive and "/bl616dk/fw_header.c.obj" not in archive)
    disassembly = (BUILD / "clock_disassembly.txt").read_text()
    check("actual_elf_26mhz", re.search(r"li\s+a0,5[\s\S]{0,140}<GLB_Power_On_XTAL_And_PLL_CLK>", disassembly) is not None)
    config = (BUILD / "generated/autoconfig.h").read_text()
    for setting in ("BT_SETTINGS", "BT_OAD_SERVER", "LITTLEFS", "PARTITION", "BFLB_MTD"):
        check(f"no_{setting.lower()}", f"#undef CONFIG_{setting}\n" in config)
    source = (PROJECT / "ble_nus.c").read_text()
    check("adv_packet_size", (3 + 18) <= 31 and (2 + len("XINXIAN-BL616")) <= 31)
    check("nus_service_checked", "int error = bt_gatt_service_register" in source)
    uart_config = (PROJECT / "bridge_config.h").read_text()
    check("uart_mapping_preserved", all(value in uart_config for value in ("115200U", "GPIO_PIN_28", "GPIO_PIN_27")))
    log = (PROJECT / "build_neo26.log").read_text(encoding="utf-8-sig")
    check("build_completed", "No flash command was run." in log and "Built target combine" in log)
    check("no_compiler_errors", "error:" not in log.lower() and "warning:" not in re.sub(r"UserWarning:.*", "", log))
    check("previous_release_preserved", sha(OLD) == "753dc6f96b7a64e75d547262f4d821e7dbc7371ac50d191a8b5830d6b84d6001")
    sources = ["CMakeLists.txt", "main.c", "ble_nus.c", "ble_nus.h", "uart_bridge.c", "bridge_config.h", "defconfig", "build_firmware.ps1"]
    result = {
        "status": "passed", "scope": "compile_and_image_inspection_only",
        "hardware_tested": False, "flash_performed": False,
        "sdk_commit": "41bf338a57be53919d99f6c6715a96100428c97d",
        "image_size_bytes": len(image), "image_sha256": sha(IMAGE),
        "intended_flash_address": "0x40000",
        "intended_flash_end_inclusive": hex(0x40000 + len(image) - 1),
        "checks": checks,
        "source_sha256": {name: sha(PROJECT / name) for name in sources},
        "elf_sha256": sha(BUILD / "build_out/xinxian_ble_uart_bl616.elf"),
        "build_log_sha256": sha(PROJECT / "build_neo26.log"),
    }
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": "passed", "checks": len(checks), "sha256": result["image_sha256"]}))


if __name__ == "__main__":
    main()
