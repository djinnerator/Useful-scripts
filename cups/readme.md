# printjob

An interactive Bash wrapper for CUPS (`lp`, `lpstat`, and `lpoptions`) on Ubuntu and Debian-based Linux distributions. `printjob` streamlines command-line printing by combining direct CLI arguments with interactive fallback menus for printer selection, current-directory file picking, hardware-queried media sizes, formatting options, pre-print confirmation, and post-submission queue tracking.

---

## Features

- **Flexible Argument Modes:** Run with zero, one, or two positional arguments depending on whether you want to specify the printer and file upfront or pick them from numbered menus.
- **Dynamic Printer Discovery:** Automatically queries available CUPS destinations via `lpstat -e` when no printer name is supplied.
- **Current-Directory File Picker:** Scans the current working directory (`pwd`) for readable regular files (safely handling filenames with spaces) when no filename is passed.
- **Interactive Print Options (`-o` / `--options`):**
  - **Copies:** Validates positive integer copy counts (`-n`).
  - **Dynamic Paper Size:** Queries the selected printer's PPD via `lpoptions` to present a menu of supported media sizes (with a manual input fallback for raw queues).
  - **Duplex Printing:** Supports both long-edge and short-edge two-sided binding.
  - **Orientation:** Toggles landscape printing.
  - **Page Ranges:** Prints specific page subsets (e.g., `1-4,7,9-12`).
  - **Scaling:** Toggles `fit-to-page` scaling.
- **Safety Confirmation Gate:** Displays a complete job summary (target file, destination printer, and compiled `lp` flags) and prompts for confirmation before sending the job.
- **Job Tracking & Queue Status:** Captures the assigned CUPS Job ID from `lp` output and immediately reports printer state (`lpstat -p`) and active queue items (`lpstat -o`).

---

## Prerequisites

- **OS:** Ubuntu / Linux with Bash 4.0+ (`mapfile` support)
- **CUPS Client Utilities:** Provided by `cups-client` and `cups-bsd` (pre-installed on standard Ubuntu Desktop installations).

To verify or install the required CUPS CLI utilities on Ubuntu:

```bash
sudo apt update && sudo apt install -y cups-client
```

---

## Installation

### 1. Make the script executable

Save the script as `printjob` (without the `.sh` extension) and grant execution permissions:

```bash
chmod +x printjob
```

### 2. Add to your system PATH

**Option A: User-local installation (Recommended)**
Move the script to `~/.local/bin` so it is available to your user account without requiring `sudo`:

```bash
mkdir -p ~/.local/bin
mv printjob ~/.local/bin/
```

If `~/.local/bin` is not yet in your `PATH`, add it to `~/.bashrc` and reload:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Option B: System-wide installation**
Move the script to `/usr/local/bin` so all users on the machine can run it:

```bash
sudo mv printjob /usr/local/bin/
```

---

## Usage

```text
printjob [-o|--options] [-h|--help] [[printer_name] <filename>]
```

### Invocation Modes

| Command | Printer Selection | File Selection | Print Options |
| :--- | :--- | :--- | :--- |
| `printjob` | Interactive menu | Interactive menu (`pwd`) | Printer defaults |
| `printjob -o` | Interactive menu | Interactive menu (`pwd`) | Interactive prompts |
| `printjob <file>` | Interactive menu | Uses `<file>` | Printer defaults |
| `printjob -o <file>` | Interactive menu | Uses `<file>` | Interactive prompts |
| `printjob <printer> <file>` | Uses `<printer>` | Uses `<file>` | Printer defaults |
| `printjob -o <printer> <file>` | Uses `<printer>` | Uses `<file>` | Interactive prompts |

### Flags

- `-o`, `--options`: Launch the interactive configuration prompts for copies, media size, duplexing, landscape orientation, page ranges, and scaling. Can be placed before, between, or after positional arguments.
- `-h`, `--help`: Display the usage syntax and exit.

---

## Interactive Options Reference

When `-o` or `--options` is passed, `printjob` prompts for the following settings and translates them into standard CUPS `lp` arguments:

| Prompt | User Input | Generated `lp` Argument |
| :--- | :--- | :--- |
| **Number of copies** | Positive integer (or `Enter` for 1) | `-n <count>` |
| **Paper size** | Menu selection via `lpoptions` (or manual string) | `-o media=<size>` |
| **Two-sided (duplex)** | `y` + `l` (long edge) or `s` (short edge) | `-o sides=two-sided-long-edge` or `-o sides=two-sided-short-edge` |
| **Landscape** | `y` | `-o landscape` |
| **Page ranges** | Range string (e.g., `1-4,7,9-12`) | `-o page-ranges=1-4,7,9-12` |
| **Scale to fit page** | `y` | `-o fit-to-page` |

---

## Examples

### 1. Fully Interactive Mode (Zero Arguments + Options)

Run `printjob -o` inside a directory containing documents to select both the printer and the file from menus:

```text
$ printjob -o
Available printers:
1) Office_LaserJet
2) Home_Inkjet
Select a printer (enter number): 1

Available files in /home/user/Documents:
1) invoice.pdf
2) notes.txt
3) report_final.pdf
Select a file to print (enter number): 3

--- Configure Print Options ---
Number of copies (press Enter for 1): 2
Change paper size from printer default? (y/N): y
Supported paper sizes (* indicates current printer default):
1) *Letter
2) Legal
3) A4
Select paper size (enter number): 1
Enable two-sided (duplex) printing? (y/N): y
Bind on (l)ong edge or (s)hort edge? [L/s]: l
Enable landscape orientation? (y/N): n
Specify page ranges (e.g., 1-4,7,9-12) or press Enter for all: 1-5
Scale document to fit page? (y/N): y

=== Print Job Summary ===
File:    report_final.pdf
Printer: Office_LaserJet
Options: -n 2 -o media=Letter -o sides=two-sided-long-edge -o page-ranges=1-5 -o fit-to-page
=========================
Send this job to the printer? (y/N): y
Sending 'report_final.pdf' to printer 'Office_LaserJet'...
request id is Office_LaserJet-104 (1 file(s))
Captured Job ID: Office_LaserJet-104

=== Print Queue Status (Office_LaserJet) ===
printer Office_LaserJet now printing Office_LaserJet-104. enabled since Sat 31 Oct 2026 02:50:12 AM EDT
Office_LaserJet-104     user             142336   Sat 31 Oct 2026 02:50:12 AM EDT
============================================
```

### 2. Quick Print with Known File and Printer

Send `slides.pdf` directly to `Office_LaserJet` using default printer settings:

```bash
printjob Office_LaserJet slides.pdf
```

### 3. Specify File Only and Configure Options

Choose the printer and formatting options interactively for a specific file path:

```bash
printjob --options ~/Downloads/shipping_label.pdf
```

---

## Troubleshooting

- **`Error: No printers found via lpstat.`**
  Ensure the CUPS service is running (`sudo systemctl status cups`) and at least one printer is configured in Ubuntu Settings or at `http://localhost:631`.
- **`Could not query printer sizes. Enter paper size manually...`**
  The selected printer uses a raw queue or driverless configuration without a local PPD `PageSize` definition. Enter a standard CUPS media name manually (such as `Letter`, `Legal`, or `A4`).
- **`Error: No readable files found in the current directory.`**
  The current directory contains only subdirectories, hidden dotfiles, or files without read permissions for your user account.
