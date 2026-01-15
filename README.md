# gasm (Gopher in Assembly)

**A bare-metal i386 Gopher server for Linux.**

`gasm` is a dependency-free Gopher server written in pure x86 Assembly. It is designed to run on the most resource-constrained hardware imaginable—from a rusty 1990s 386DX to a modern potato.

No libc. No runtime. No dynamic allocation. Just pure `int 0x80` syscalls.

## ⚡ The Stats

| Metric | GASM | Typical Web Server |
| :--- | :--- | :--- |
| **Binary Size** | **~2.8 KB** | 50MB+ |
| **RAM Usage** | **~24 KB** | 100MB+ |
| **Dependencies** | **0** | ∞ |
| **Min CPU** | **Intel 386 (1985)** | Core i7 |

## 🛠 Features

* **Zero Runtime:** Runs natively on the bare metal of the OS.
* **Static Memory:** Uses global buffers and page-aligned memory. No heap, no `malloc`, no leaks.
* **Legacy Networking:** Uses the `socketcall` (syscall 102) interface for maximum compatibility with older Linux kernels (2.4+).
* **Security:**
    * Strict input size limiting (Buffer Overflow protection).
    * Sanitizes path traversal (`..`).
    * Runs as an unprivileged user (Port 7890).
* **Protocol Support:**
    * Dynamic Directory Listings (Type 1)
    * Text Files (Type 0)
    * Binaries / Images (Type 9)

## 🦕 Hardware Support

GASM targets the **i386** (IA-32) instruction set.

* **Minimum:** Intel 80386DX, 4MB RAM, Linux 2.4.
* **Maximum:** Any modern x86_64 CPU (runs natively via legacy mode).

*Why Linux 2.4?* It introduced `getdents64`, allowing us to list directories efficiently in a single syscall. This prevents I/O thrashing on ancient, slow hard drives.

## 🚀 Build & Run

**Prerequisites:** `nasm` and `ld` (binutils).

```bash
# 1. Build (Cross-compiles 32-bit ELF on 64-bit systems)
make

# 2. Setup content
mkdir content
echo "Hello from Assembly" > content/hello.txt

# 3. Run
./gasm content

```

**Test:**

```bash
curl gopher://localhost:7890

```
