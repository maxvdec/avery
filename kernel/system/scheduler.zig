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
    current_queue: usize = 0,
    last_schedule_time: u32 = 0,
    total_processes: u32 = 0,

    pub fn init(self: *Scheduler) void {
        @setRuntimeSafety(false);
        for (0..5) |i| {
            self.ready_queues[i] = mem.Array(*Process).initKernel();
        }
        self.last_schedule_time = getCurrentTicks();
        pit.setSchedulerCallback(timerInterruptHandler);
    }

    pub fn addProcess(self: *Scheduler, process: *Process) void {
        @setRuntimeSafety(false);

        if (process.state == .Ready) {
            const priority_level = @intFromEnum(process.priority);
            self.ready_queues[priority_level].append(process);
            self.total_processes += 1;
        }
        out.preserveMode();
        out.switchToSerial();
        scheduler.printStatistics();
        out.restoreMode();
    }

    pub fn removeProcess(self: *Scheduler, process: *Process) void {
        @setRuntimeSafety(false);

        for (0..5) |i| {
            for (0..self.ready_queues[i].len) |j| {
                const p = self.ready_queues[i].get(j).?;
                if (p.pid == process.pid) {
                    _ = self.ready_queues[i].remove(j);
                    self.total_processes -= 1;
                    return;
                }
            }
        }
        out.preserveMode();
        out.switchToSerial();
        scheduler.printStatistics();
        out.restoreMode();
    }

    pub fn findNextProcess(self: *Scheduler) ?*Process {
        @setRuntimeSafety(false);

        for (0..5) |i| {
            const queue = self.ready_queues[i].coerce();
            for (queue) |p| {
                p.updatePriority();
            }
        }

        for (0..5) |i| {
            const queue = self.ready_queues[i].coerce();
            if (queue.len > 0) {
                const next_proc = queue[0];

                _ = self.ready_queues[i].remove(0);

                if (next_proc.time_slice_remaining == 0 or next_proc.quantum_count >= next_proc.priority.getQuantumBonus()) {
                    next_proc.time_slice_remaining = next_proc.priority.getTimeSlice();
                    next_proc.quantum_count = 0;
                }

                return next_proc;
            }
        }

        return null;
    }

    pub fn schedule(self: *Scheduler) void {
        @setRuntimeSafety(false);

        if (current_process != null and current_process.?.state == .Running) {
            current_process.?.suspendProcess();
            if (current_process.?.state == .Ready) {
                self.addProcess(current_process.?);
            }
        }

        const next_process = self.findNextProcess();

        if (next_process) |p| {
            p.quantum_count += 1;

            const current_time = getCurrentTicks();
            p.time_slice_start = current_time;
            p.time_slice_remaining = p.priority.getTimeSlice();

            current_process = p;

            p.run();
        } else {
            const idle_proc = proc.createFallbackProcess();
            if (idle_proc) |idle| {
                idle.run();
            } else {
                out.println("No processes available to run, system is idle.");
                asm volatile ("hlt");
            }
        }

        self.last_schedule_time = getCurrentTicks();
        out.preserveMode();
        out.switchToSerial();
        scheduler.printStatistics();
        out.restoreMode();
    }

    pub fn yield(self: *Scheduler) void {
        @setRuntimeSafety(false);
        if (current_process != null) {
            current_process.?.time_slice_remaining = 0;
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
pub var scheduler: Scheduler = .{
    .ready_queues = [_]mem.Array(*Process){mem.Array(*Process).initKernel()} ** 5,
};

fn timerInterruptHandler() void {
    @setRuntimeSafety(false);
    if (current_process) |p| {
        const current_time = getCurrentTicks();
        const time_used = current_time - p.time_slice_start;

        const total_time_slice = p.priority.getTimeSlice();

        if (time_used >= total_time_slice) {
            out.preserveMode();
            out.switchToSerial();
            out.println("Process time slice expired, scheduling next process.");
            out.restoreMode();
            scheduler.schedule();
        }
    }

    out.restoreMode();
}

pub fn initScheduler() void {
    @setRuntimeSafety(false);
    out.preserveMode();
    out.switchToSerial();
    scheduler.printStatistics();
    out.restoreMode();
    if (!pit.initialized) {
        pit.init();
    }

    scheduler.init();
}

pub fn scheduleNext() void {
    @setRuntimeSafety(false);
    scheduler.schedule();
}

pub fn yieldCPU() void {
    @setRuntimeSafety(false);
    scheduler.yield();
}

pub fn getCurrentProcess() ?*Process {
    return current_process;
}

pub fn printSchedulerStats() void {
    @setRuntimeSafety(false);
    scheduler.printStatistics();
}
