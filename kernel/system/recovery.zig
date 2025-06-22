const ata = @import("ata");
const out = @import("output");
const dir_structure = @import("dir_structure");
const vfs = @import("vfs");
const in = @import("input");
const mem = @import("memory");
const sys = @import("system");
const time = @import("time");

pub fn systemIntegrityChecks(drive: *ata.AtaDrive) void {
    // These are the following system integrity checks that the program
    // First, we need to check for the important driver directory
    if (!vfs.directoryExists(drive, &dir_structure.DRIVERS, 0)) {
        recovery(drive);
    }

    if (!vfs.directoryExists(drive, &dir_structure.SYSTEM, 0)) {
        recovery(drive);
    }

    if (!vfs.directoryExists(drive, &dir_structure.OS, 0)) {
        recovery(drive);
    }
}

fn recovery(drive: *ata.AtaDrive) void {
    out.clear();
    out.println("Welcome to the Avery Kernel Recovery System");
    out.println("The System Integrity Checks have failed, meaning your system is corrupted");
    out.println("Some files are missing or damaged and the kernel cannot boot properly");
    out.println("\nYou could use a recovery disk or make the Avery Kernel try to repair the damaged files");
    out.println("If you have the ability, use the recovery disk (not implemented yet), since repairing may mean reinstalling the operating system in some cases");
    out.println("\n\nType 'r' to start the recovery process, 'b' for introducing a backup system and 'h' for halting the system");

    out.print("> ");
    const opt = in.readln();

    if (mem.compareBytes(u8, "h", opt)) {
        out.println("Halting the system...");
        while (true) {}
    } else if (mem.compareBytes(u8, "b", opt)) {
        out.println("Comencing backup process...");
        // Implement backup process here
        sys.panic("Feature not implemented yet");
    } else if (mem.compareBytes(u8, "r", opt)) {
        recreateFiles(drive);
        out.println("\nRecovery process finished. Booting in 5 seconds...");
        time.wait(5000);
        out.clear();
    } else {
        sys.panic("Invalid option");
    }
}

fn recreateFiles(drive: *ata.AtaDrive) void {
    if (!vfs.directoryExists(drive, &dir_structure.SYSTEM, 0)) {
        out.println("Creating system directory and structure...");
        var result = vfs.makeNewDirectory(drive, &dir_structure.SYSTEM, 0);
        if (result == null) {
            sys.panic("Failed to create system directory");
        }
        result = vfs.makeNewDirectory(drive, &dir_structure.OS, 0);
        if (result == null) {
            sys.panic("Failed to create OS directory");
        }
        result = vfs.makeNewDirectory(drive, &dir_structure.BINARIES, 0);
        if (result == null) {
            sys.panic("Failed to create BINARIES directory");
        }
        result = vfs.makeNewDirectory(drive, &dir_structure.DRIVERS, 0);
        if (result == null) {
            sys.panic("Failed to create DRIVERS directory");
        }
        result = vfs.makeNewDirectory(drive, &dir_structure.APPLICATIONS, 0);
        if (result == null) {
            sys.panic("Failed to create APPLICATIONS directory");
        }
        return;
    }

    if (!vfs.directoryExists(drive, &dir_structure.OS, 0)) {
        const result = vfs.makeNewDirectory(drive, &dir_structure.OS, 0);
        if (result == null) {
            sys.panic("Failed to create OS directory");
        }
    }

    if (!vfs.directoryExists(drive, &dir_structure.BINARIES, 0)) {
        const result = vfs.makeNewDirectory(drive, &dir_structure.BINARIES, 0);
        if (result == null) {
            sys.panic("Failed to create BINARIES directory");
        }
    }

    if (!vfs.directoryExists(drive, &dir_structure.DRIVERS, 0)) {
        const result = vfs.makeNewDirectory(drive, &dir_structure.DRIVERS, 0);
        if (result == null) {
            sys.panic("Failed to create DRIVERS directory");
        }
    }

    if (!vfs.directoryExists(drive, &dir_structure.APPLICATIONS, 0)) {
        const result = vfs.makeNewDirectory(drive, &dir_structure.APPLICATIONS, 0);
        if (result == null) {
            sys.panic("Failed to create APPLICATIONS directory");
        }
    }
}
