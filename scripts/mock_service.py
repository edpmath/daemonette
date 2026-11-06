#!/usr/bin/env python3
import sys
import time
import signal

# Unbuffered output for real-time log streaming
sys.stdout.reconfigure(line_buffering=True)

# ANSI escape codes
CYAN   = "\033[36m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
BOLD   = "\033[1m"
RESET  = "\033[0m"
DIM    = "\033[2m"

mode = sys.argv[1] if len(sys.argv) > 1 else "frontend"

def sig_handler(sig, frame):
    sys.exit(0)

signal.signal(signal.SIGINT, sig_handler)
signal.signal(signal.SIGTERM, sig_handler)

if mode == "backend":
    # Allocate ~35 MB of RAM for realistic RSS reading
    _buffer = bytearray(35 * 1024 * 1024)

    print(f"{GREEN}{BOLD}INFO{RESET}:     Started server process [9142]")
    print(f"{GREEN}{BOLD}INFO{RESET}:     Waiting for application startup.")
    print(f"{GREEN}{BOLD}INFO{RESET}:     Application startup complete.")
    print(f"{GREEN}{BOLD}INFO{RESET}:     Uvicorn running on {BOLD}http://127.0.0.1:8000{RESET} (Press CTRL+C to quit)")

    endpoints = [
        "GET /health HTTP/1.1 200 OK",
        "GET /api/v1/services HTTP/1.1 200 OK",
        "POST /api/v1/auth/token HTTP/1.1 200 OK",
        "GET /api/v1/metrics HTTP/1.1 200 OK",
        "GET /api/v1/services/logs HTTP/1.1 200 OK",
    ]

    i = 0
    while True:
        time.sleep(3)
        print(f"{GREEN}{BOLD}INFO{RESET}:     127.0.0.1:54210 - \"{endpoints[i % len(endpoints)]}\"")
        i += 1

else:
    # Frontend: Allocate ~25 MB of RAM
    _buffer = bytearray(25 * 1024 * 1024)

    print(f"\n{CYAN}{BOLD}  VITE v5.2.0{RESET}  {GREEN}ready in 284 ms{RESET}\n")
    print(f"  {GREEN}➜{RESET}  {BOLD}Local:{RESET}   {CYAN}http://localhost:5173/{RESET}")
    print(f"  {GREEN}➜{RESET}  {BOLD}Network:{RESET} {DIM}use --host to expose{RESET}")
    print(f"  {GREEN}➜{RESET}  press {BOLD}h + enter{RESET} to show help\n")

    events = [
        f"{DIM}[vite]{RESET} 17:15:02 {GREEN}hmr update{RESET} /src/components/TrayIndicator.vue",
        f"{DIM}[vite]{RESET} 17:15:08 {CYAN}GET{RESET} /api/services {GREEN}200 OK{RESET} 1.4ms",
        f"{DIM}[vite]{RESET} 17:15:15 {CYAN}GET{RESET} /src/main.ts {GREEN}200 OK{RESET} 2.1ms",
        f"{DIM}[vite]{RESET} 17:15:22 {GREEN}hmr update{RESET} /src/views/LogViewer.vue",
        f"{DIM}[vite]{RESET} 17:15:30 {YELLOW}POST{RESET} /api/services/restart {GREEN}200 OK{RESET} 3.8ms",
    ]

    i = 0
    while True:
        time.sleep(2.5)
        print(events[i % len(events)])
        i += 1
