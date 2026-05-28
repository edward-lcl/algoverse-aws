#!/usr/bin/env python3
"""Cross-platform local compute inventory for Algoverse project setup.

Prints JSON so agents and humans can decide whether local compute is viable
before paying for cloud GPUs or premium API loops.
"""

from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
from typing import Any


def run(cmd: list[str], timeout: int = 8) -> str | None:
    try:
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def bytes_to_gb(value: int | float | None) -> float | None:
    if value is None:
        return None
    return round(float(value) / (1024**3), 1)


def memory_gb() -> float | None:
    system = platform.system()
    if system == "Darwin":
        out = run(["sysctl", "-n", "hw.memsize"])
        return bytes_to_gb(int(out)) if out and out.isdigit() else None
    if system == "Linux":
        try:
            with open("/proc/meminfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        return round(int(line.split()[1]) / 1024 / 1024, 1)
        except OSError:
            return None
    if system == "Windows":
        out = run(["powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"])
        return bytes_to_gb(int(out)) if out and out.strip().isdigit() else None
    return None


def disk_free_gb(path: str = ".") -> float | None:
    try:
        usage = shutil.disk_usage(path)
    except OSError:
        return None
    return bytes_to_gb(usage.free)


def nvidia_gpus() -> list[dict[str, Any]]:
    if not shutil.which("nvidia-smi"):
        return []
    out = run([
        "nvidia-smi",
        "--query-gpu=name,memory.total,driver_version",
        "--format=csv,noheader,nounits",
    ])
    if not out:
        return []
    gpus = []
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 2:
            gpus.append({
                "name": parts[0],
                "vram_gb": round(float(parts[1]) / 1024, 1),
                "driver": parts[2] if len(parts) > 2 else None,
            })
    return gpus


def apple_gpu() -> dict[str, Any] | None:
    if platform.system() != "Darwin":
        return None
    chip = run(["sysctl", "-n", "machdep.cpu.brand_string"])
    sp = run(["system_profiler", "SPDisplaysDataType"], timeout=15) or ""
    names = []
    for line in sp.splitlines():
        line = line.strip()
        if line.startswith("Chipset Model:"):
            names.append(line.split(":", 1)[1].strip())
    return {"chip": chip, "gpu_names": names}


def recommendation(ram_gb: float | None, gpus: list[dict[str, Any]], is_apple: bool) -> str:
    max_vram = max((g.get("vram_gb", 0) for g in gpus), default=0)
    if max_vram >= 48:
        return "Strong local GPU: use for pilots, local inference, and some fine-tuning before SageMaker."
    if max_vram >= 24:
        return "Useful local GPU: try 1-7B pilots and small fine-tunes locally; use cloud for long runs."
    if max_vram >= 12:
        return "Pilot-capable GPU: local inference/debugging is reasonable; use cloud for training."
    if is_apple and ram_gb and ram_gb >= 32:
        return "Apple Silicon is useful for local inference and debugging; use SageMaker for CUDA training."
    if ram_gb and ram_gb >= 32:
        return "CPU/RAM is okay for preprocessing and small baselines; use cloud for GPU workloads."
    return "Local machine is limited; prefer cloud for serious model work."


def main() -> None:
    system = platform.system()
    ram = memory_gb()
    nvidia = nvidia_gpus()
    apple = apple_gpu()
    payload = {
        "system": system,
        "machine": platform.machine(),
        "python": platform.python_version(),
        "cpu": platform.processor() or None,
        "ram_gb": ram,
        "disk_free_gb": disk_free_gb(os.getcwd()),
        "nvidia_gpus": nvidia,
        "apple_gpu": apple,
        "recommendation": recommendation(ram, nvidia, system == "Darwin"),
    }
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()

