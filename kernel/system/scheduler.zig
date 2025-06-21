const vmm = @import("virtual_mem");
const proc = @import("process");
const out = @import("output");
const alloc = @import("allocator");
const kalloc = @import("kern_allocator");
const ext = @import("extensions");
const sys = @import("system");
const mem = @import("memory");
const pit = @import("pit");

const ProcessState = proc.ProcessState;
const ProcessContext = proc.ProcessContext;
const Process = proc.Process;

pub const ProcessPriority = enum(u8) {
    Critical = 0,
    High = 1,
    Normal = 2,
    Low = 3,
    Idle = 4,

    pub fn getTimeSlice(self: ProcessPriority) u32 {
        return switch (self) {
            .Critical => 50, // in milliseconds
            .High => 40,
            .Normal => 30,
            .Low => 20,
            .Idle => 10,
        };
    }

    pub fn getQuantumBonus(self: ProcessPriority) u32 {
        return switch (self) {
            .Critical => 3, // resulting in 150 ms
            .High => 2, // resulting in 80 ms
            .Normal => 1, // resulting in 30 ms
            .Low => 1, // resulting in 20 ms
            .Idle => 1, // resulting in 10 ms
        };
    }
};

extern fn memcpy(
    dest: [*]u8,
    src: [*]const u8,
    len: usize,
) [*]u8;

fn getCurrentTicks() u32 {
    if (!pit.initialized) {
        pit.init();
    }
    return pit.timerTicks;
}

pub const Scheduler = struct {
    ready_queues: [5]mem.Array(*Process),
    blocked_queue: mem.Array(*Process),
    blocked_processes: u32 = 0,
    current_queue: usize = 0,
    last_schedule_time: u32 = 0,
    total_processes: u32 = 0,
    scheduling_in_progress: bool = false,
    redo_scheduling: bool = false,

    pub fn init(self: *Scheduler) void {
        @setRuntimeSafety(false);
        for (0..5) |i| {
            self.ready_queues[i] = mem.Array(*Process).initKernel();
        }
        self.blocked_queue = mem.Array(*Process).initKernel();
        self.last_schedule_time = getCurrentTicks();
        self.scheduling_in_progress = false;
        pit.setSchedulerCallback(timerInterruptHandler);

        // Create the idle process
        Process.createIdleProcess();
    }

    pub fn addProcess(self: *Scheduler, process: *Process) void {
        @setRuntimeSafety(false);

        if (process.pid == 0) return;

        if (process.state == .Ready) {
            const priority_level = @intFromEnum(process.priority);
            if (self.isProcessInQueues(process)) {
                return;
            }

            // Add to the END of the queue for round-robin behavior
            self.ready_queues[priority_level].append(process);
            self.total_processes += 1;

            out.preserveMode();
            out.switchToSerial();
            out.print("Added process PID ");
            out.printn(process.pid);
            out.print(" with priority ");
            out.printn(@intFromEnum(process.priority));
            out.print(" to queue position ");
            out.printn(self.ready_queues[priority_level].len - 1);
            out.println("");
            out.restoreMode();
        } else if (process.state == .Blocked) {
            self.blocked_queue.append(process);
            self.blocked_processes += 1;
        } else {
            return;
        }
    }

    pub fn refreshInterrupts() void {
        pit.setSchedulerCallback(timerInterruptHandler);
    }

    fn isProcessInQueues(self: *Scheduler, process: *Process) bool {
        @setRuntimeSafety(false);

        for (0..5) |i| {
            const queue = self.ready_queues[i].coerce();
            for (queue) |p| {
                if (p.pid == process.pid) {
                    return true;
                }
            }
        }
        return false;
    }

    fn isProcessBlocked(self: *Scheduler, process: *Process) bool {
        for (self.blocked_queue.iterate()) |p| {
            if (p.pid == process.pid) {
                return true;
            }
        }
        return false;
    }

    pub fn removeProcess(self: *Scheduler, process: *Process) void {
        @setRuntimeSafety(false);

        if (process.pid == 0) return;

        for (0..5) |i| {
            var j: usize = 0;
            while (j < self.ready_queues[i].len) {
                const p = self.ready_queues[i].get(j) orelse break;
                if (p.pid == process.pid) {
                    _ = self.ready_queues[i].remove(j);
                    if (self.total_processes > 0) {
                        self.total_processes -= 1;
                    }

                    out.preserveMode();
                    out.switchToSerial();
                    out.print("Removed process ");
                    out.printn(process.pid);
                    out.print(" from priority queue ");
                    out.printn(i);
                    out.println("");
                    out.restoreMode();
                    return;
                }
                j += 1;
            }
        }

        var j: usize = 0;
        while (j < self.blocked_queue.len) {
            const proc_in_queue = self.blocked_queue.get(j) orelse break;
            if (proc_in_queue.pid == process.pid) {
                _ = self.blocked_queue.remove(j);
                if (self.total_processes > 0) {
                    self.total_processes -= 1;
                }

                out.preserveMode();
                out.switchToSerial();
                out.print("Removed process ");
                out.printn(process.pid);
                out.print(" from blocked queue");
                out.println("");
                out.restoreMode();
                return;
            }
            j += 1;
        }
    }

    pub fn blockProcess(self: *Scheduler, process: *Process) void {
        @setRuntimeSafety(false);

        if (process.pid == 0) return;

        self.removeProcess(process);

        process.state = .Blocked;

        self.addProcess(process);

        out.preserveMode();
        out.switchToSerial();
        out.print("Blocked process ");
        out.printn(process.pid);
        out.print(" in blocked queue");
        out.println("");
        out.restoreMode();
    }

    pub fn unblockProcess(self: *Scheduler, process: *Process) void {
        @setRuntimeSafety(false);

        if (process.pid == 0) return;

        self.removeProcess(process);

        process.state = .Ready;

        self.addProcess(process);

        out.preserveMode();
        out.switchToSerial();
        out.print("Unblocked process ");
        out.printn(process.pid);
        out.print(" in ready queue");
        out.println("");
        out.restoreMode();

        self.redo_scheduling = true;
    }

    pub fn findNextProcess(self: *Scheduler) ?*Process {
        @setRuntimeSafety(false);

        const current_time = getCurrentTicks();
        const aging_threshold = 120;

        for (0..5) |i| {
            const queue = self.ready_queues[i].coerce();
            for (queue) |p| {
                if (p.pid != 0) {
                    p.updatePriority();

                    const wait_time = current_time - p.last_scheduled;

                    if (wait_time > (aging_threshold / p.priority.getQuantumBonus()) and i > 0) {
                        var j: usize = 0;
                        while (j < self.ready_queues[i].len) {
                            const proc_in_queue = self.ready_queues[i].get(j) orelse break;
                            if (proc_in_queue.pid == p.pid) {
                                _ = self.ready_queues[i].remove(j);
                                self.ready_queues[i - 1].append(p);
                                break;
                            }
                            j += 1;
                        }
                    }
                }
            }
        }

        for (0..5) |i| {
            if (self.ready_queues[i].len > 0) {
                const next_proc = self.ready_queues[i].get(0) orelse continue;

                _ = self.ready_queues[i].remove(0);
                if (self.total_processes > 0) {
                    self.total_processes -= 1;
                }

                next_proc.last_scheduled = current_time;

                if (next_proc.time_slice_remaining == 0 or
                    next_proc.quantum_count >= next_proc.priority.getQuantumBonus())
                {
                    next_proc.time_slice_remaining = next_proc.priority.getTimeSlice();
                    next_proc.quantum_count = 0;
                }

                return next_proc;
            }
        }

        if (current_process != null) {
            return current_process;
        }

        return null;
    }

    pub fn schedule(self: *Scheduler) void {
        @setRuntimeSafety(false);

        if (self.scheduling_in_progress) {
            return;
        }
        self.scheduling_in_progress = true;

        if (current_process) |p| {
            if (p.state == .Blocked) {
                current_process = null;
            }
        }

        const next_process = self.findNextProcess();

        if (next_process) |p| {
            p.quantum_count += 1;

            const current_time = getCurrentTicks();
            p.time_slice_start = current_time;
            p.time_slice_remaining = p.priority.getTimeSlice();

            current_process = p;

            self.scheduling_in_progress = false;
            p.run();
        } else {
            out.preserveMode();
            out.switchToSerial();
            out.println("No processes available, creating idle process");
            out.restoreMode();

            sys.panic("No process to run. Idle process was killed. This could be related to a security issue.");
        }

        self.last_schedule_time = getCurrentTicks();
    }

    pub fn yield(self: *Scheduler) void {
        @setRuntimeSafety(false);

        if (current_process) |p| {
            p.time_slice_remaining = 0;
        }
        self.schedule();
    }

    pub fn printStatistics(self: *Scheduler) void {
        @setRuntimeSafety(false);
        out.println("=== Scheduler Statistics ===");
        out.print("Total processes: ");
        out.printn(self.total_processes);
        out.println("");

        for (0..5) |i| {
            const queue_data = self.ready_queues[i].coerce();
            out.print("Priority ");
            out.printn(i);
            out.print(" queue: ");
            out.printn(queue_data.len);
            out.println(" processes");

            for (queue_data) |p| {
                out.print("  PID ");
                out.printn(p.pid);
                out.print(" - CPU time: ");
                out.printn(p.total_cpu_time);
                out.print("ms, Wait time: ");
                out.printn(p.wait_time);
                out.println("ms");
            }
        }

        if (current_process) |p| {
            out.print("Current process: PID ");
            out.printn(p.pid);
            out.print(" Priority: ");
            out.printn(@intFromEnum(p.priority));
            out.print(" Time remaining: ");
            out.printn(p.time_slice_remaining);
            out.println("ms");
        }
        out.println("========================");
    }
};

pub var current_process: ?*Process = null;
pub var scheduler: ?*Scheduler = null;

fn timerInterruptHandler() void {
    @setRuntimeSafety(false);

    if (scheduler.?.scheduling_in_progress) {
        return;
    }

    if (scheduler.?.redo_scheduling) {
        scheduler.?.redo_scheduling = false;
        scheduler.?.schedule();
        return;
    }

    if (current_process) |p| {
        const current_time = getCurrentTicks();
        const time_used = current_time - p.time_slice_start;
        const total_time_slice = p.priority.getTimeSlice();

        p.total_cpu_time += time_used;

        if (time_used >= total_time_slice) {
            scheduler.?.schedule();
        } else {
            if (p.time_slice_remaining > time_used) {
                p.time_slice_remaining -= time_used;
            } else {
                p.time_slice_remaining = 0;
            }
        }
    }
}

pub fn initScheduler() void {
    @setRuntimeSafety(false);
    if (!pit.initialized) {
        pit.init();
    }

    scheduler = kalloc.storeKernel(Scheduler);
    scheduler.?.init();
}

pub fn scheduleNext() void {
    @setRuntimeSafety(false);
    scheduler.?.schedule();
}

pub fn yieldCPU() void {
    @setRuntimeSafety(false);
    scheduler.?.yield();
}

pub fn getCurrentProcess() ?*Process {
    return current_process;
}

pub fn printSchedulerStats() void {
    @setRuntimeSafety(false);
    scheduler.?.printStatistics();
}
