# EnochOS

A modern microkernel-based operating system written in Zig, featuring Mach IPC, enhanced memory management, and a flexible VFS system.

## Features

### Core Kernel
- **Microkernel Architecture** - Clean separation between kernel and user-space services
- **Mach IPC Subsystem** - Ports, messages, and notifications for inter-process communication
- **Enhanced Buddy Allocator** - Transparent Huge Pages (THP) support with memory compaction
- **Virtual Memory Management** - Full paging support with page tables
- **Enhanced VFS** - Virtual File System with vnode caching and mount point management

### File Systems
- **FAT32 Driver** - Full FAT32 file system support with cluster caching
- **Device Files** - /dev/null, /dev/zero, /dev/random, /dev/console

### Device Management
- **Device Manager** - Bus enumeration with driver probing
- **Standard Devices** - Platform, virtual, and ISA device support
- **Keyboard Driver** - PS/2 keyboard with scan code translation
- **Timer** - PIT-based system timer with configurable frequency

### Process Management
- **Scheduler** - Cooperative multitasking with process states
- **System Calls** - Extensible syscall table for user-space interfaces
- **Process Isolation** - Separate address spaces with virtual memory

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  User Space                     │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ enoch   │  │ enoch   │  │ enochedit│       │
│  │ browse  │  │ fetch   │  │         │        │
│  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────┘
                    │ Syscalls
┌─────────────────────────────────────────────────┐
│                  Kernel Space                   │
│  ┌─────────────────────────────────────────┐   │
│  │              Mach IPC                    │   │
│  │  (Ports, Messages, Notifications)        │   │
│  └─────────────────────────────────────────┘   │
│  ┌────────────┐  ┌────────────┐               │
│  │   VFS      │  │   Device   │               │
│  │ (Enhanced) │  │  Manager   │               │
│  └────────────┘  └────────────┘               │
│  ┌────────────┐  ┌────────────┐               │
│  │   Buddy    │  │  Virtual   │               │
│  │ Allocator  │  │  Memory    │               │
│  │ (THP)      │  │  (Paging)  │               │
│  └────────────┘  └────────────┘               │
│  ┌────────────┐  ┌────────────┐               │
│  │  Scheduler │  │   Timer    │               │
│  └────────────┘  └────────────┘               │
│  ┌────────────┐  ┌────────────┐               │
│  │    IDT     │  │    GDT     │               │
│  │   (PIC)    │  │            │               │
│  └────────────┘  └────────────┘               │
└─────────────────────────────────────────────────┘
```

## Building

### Prerequisites

- Zig 0.11.0 or later
- QEMU (for testing)
- mkisofs (for ISO creation)

### Build Commands

```bash
# Build the kernel
zig build

# Build bootable ISO
zig build iso

# Run in QEMU
zig build run
```

## Project Structure

```
EnochOS/
├── build.zig          # Zig build configuration
├── kernel/
│   ├── kmain.zig      # Kernel entry point
│   ├── gdt.zig        # Global Descriptor Table
│   ├── idt.zig        # Interrupt Descriptor Table
│   ├── pic.zig        # Programmable Interrupt Controller
│   ├── x86.zig        # x86 assembly wrappers
│   ├── mem.zig        # Basic memory allocation
│   ├── pmem.zig       # Physical memory management
│   ├── buddy.zig      # Buddy allocator (basic)
│   ├── buddy_enhanced.zig  # Enhanced buddy with THP
│   ├── vmem.zig       # Virtual memory (paging)
│   ├── scheduler.zig  # Process scheduler
│   ├── timer.zig      # System timer
│   ├── keyboard.zig   # PS/2 keyboard driver
│   ├── tty.zig        # VGA text console
│   ├── syscall.zig    # System call interface
│   ├── vfs.zig        # Basic VFS
│   ├── vfs_enhanced.zig    # Enhanced VFS with caching
│   ├── device.zig     # Basic device management
│   ├── device_enhanced.zig # Enhanced device manager
│   ├── fat32.zig      # Basic FAT32 driver
│   ├── fat32_enhanced.zig  # Enhanced FAT32 with caching
│   ├── ipc.zig        # Basic IPC
│   └── ipc_mach.zig   # Mach IPC subsystem
└── apps/
    ├── enochbrowse/   # File browser
    ├── enochfetch/    # System info
    └── enochedit/     # Text editor
```

## License

This project is licensed under the **EnochOS Public Source License Version 1.0**.

See [LICENSE](LICENSE) for details.

### Third-Party Components

This project incorporates architectural concepts from:
- **Darwin/XNU** - Mach IPC and microkernel design (APSL 2.0 concepts)
- **Linux Kernel** - Memory management and VFS concepts (GPL v2 concepts)

All original code is written in Zig and licensed under EnochOS Public Source License.

## Contributing

This is a single-developer project (MelvinSGjr), but ideas and suggestions are welcome!

## Contact

- **Developer**: MelvinSGjr
- **GitHub**: @MelvinMod
- **Location**: Romania

## Roadmap

- [x] Basic kernel booting
- [x] GDT/IDT setup
- [x] Physical memory management
- [x] Enhanced buddy allocator with THP
- [x] Virtual memory (paging)
- [x] Scheduler basics
- [x] Timer and keyboard
- [x] Basic VFS
- [x] Enhanced VFS with caching
- [x] FAT32 driver
- [x] Mach IPC subsystem
- [ ] Preemptive scheduling
- [ ] Multi-core support (SMP)
- [ ] Network stack
- [ ] More system calls
- [ ] User-space process isolation
- [ ] Graphics driver (VESA)
- [ ] Shell implementation

## Acknowledgments

Inspired by the architecture and design principles of:
- Darwin/XNU (Apple)
- Linux Kernel
- MINIX 3
- Fiasco.OC

---

**EnochOS** - A modern approach to operating system design, written in Zig.
