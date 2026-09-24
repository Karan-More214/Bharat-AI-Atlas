"""
Runs the full pipeline: collect -> clean -> load.
Schedule this weekly (Windows Task Scheduler / cron) to build trend history.

Usage:
    python src/run_pipeline.py
    python src/run_pipeline.py --skip-collect   # re-clean + reload the latest raw file
"""
import argparse
import subprocess
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent


def step(script, *extra):
    print(f"\n===== {script} =====")
    subprocess.run([sys.executable, str(SRC / script), *extra], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-collect", action="store_true")
    args = parser.parse_args()
    if not args.skip_collect:
        step("collect.py")
    step("clean.py")
    step("load_to_sql.py")
    print("\nPipeline finished. Refresh your Power BI report.")
