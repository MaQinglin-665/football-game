"""Encode actual rendered frames using their recorded simulation timestamps."""
import argparse
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
parser.add_argument("--ffmpeg", default="D:/app/ffmpeg/bin/ffmpeg.exe")
args = parser.parse_args()
root = args.directory.resolve()
clips = []
for manifest in sorted(root.glob("cut_*/manifest.json")):
    data = json.loads(manifest.read_text(encoding="utf-8-sig"))
    frames = data["frames"]
    if len(frames) < 2:
        continue
    lines = []
    for index, frame in enumerate(frames):
        name = frame["file"]
        if not re.fullmatch(r"frame_\d+\.jpg", name):
            raise ValueError("Unexpected frame filename")
        duration = (frames[index + 1]["simulation_time_s"] - frame["simulation_time_s"]
                    if index + 1 < len(frames) else 1 / 24)
        if not 0 < duration < 2:
            raise ValueError("Invalid frame interval")
        lines += [f"file '{name}'", f"duration {duration:.9f}"]
    lines.append(f"file '{frames[-1]['file']}'")
    timing = manifest.parent / "timing.ffconcat"
    timing.write_text("\n".join(lines) + "\n", encoding="utf-8")
    output = manifest.parent / "clip.mp4"
    subprocess.run([args.ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
                    "-f", "concat", "-safe", "0", "-i", str(timing),
                    "-fps_mode", "vfr", "-c:v", "libx264", "-preset", "fast",
                    "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                    str(output)], check=True)
    clips.append(output.relative_to(root).as_posix())
    print(manifest.parent.name, "trigger", data["trigger"]["simulation_time_s"],
          "observed_seconds", round(frames[-1]["simulation_time_s"] - frames[0]["simulation_time_s"], 3))
if clips:
    combined = root / "clips.ffconcat"
    combined.write_text("\n".join(f"file '{path}'" for path in clips) + "\n", encoding="utf-8")
    subprocess.run([args.ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
                    "-f", "concat", "-safe", "0", "-i", str(combined), "-c", "copy",
                    "-movflags", "+faststart", str(root.parent / "扣球自然对抗_3段.mp4")], check=True)
