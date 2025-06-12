use std::env;
use std::fs;
use std::process;

use arf::ArfFile;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage(&args[0]);
        process::exit(1);
    }

    let command = &args[1];
    match command.as_str() {
        "translate" => handle_translate(&args[0], &args[2..]),
        "info" => handle_info(&args[0], &args[2..]),
        "addlib" => handle_addlib(&args[0], &args[2..]),
        _ => {
            eprintln!("Unknown command: {}", command);
            print_usage(&args[0]);
            process::exit(1);
        }
    }
}

fn print_usage(program: &str) {
    eprintln!("Usage:");
    eprintln!(
        "  {} translate <input_file> [-o output_file] [-d descriptor_file]",
        program
    );
    eprintln!("  {} info <input_file>", program);
    eprintln!("  {} addlib <input_file>", program);
}

fn handle_translate(program: &str, args: &[String]) {
    if args.is_empty() {
        eprintln!("Missing input file for translate command");
        eprintln!(
            "Usage: {} translate <input_file> [-o output_file] [-d descriptor_file]",
            program
        );
        process::exit(1);
    }

    let input_file = &args[0];
    let bytes = fs::read(input_file).unwrap_or_else(|_| {
        eprintln!("Failed to read file: {}", input_file);
        process::exit(1);
    });

    let mut output_file = "out.arf";
    let mut descriptor_file: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-o" => {
                if i + 1 < args.len() {
                    output_file = &args[i + 1];
                    i += 2;
                } else {
                    eprintln!("Missing output file path after -o");
                    process::exit(1);
                }
            }
            "-d" => {
                if i + 1 < args.len() {
                    descriptor_file = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    eprintln!("Missing descriptor file path after -d");
                    process::exit(1);
                }
            }
            _ => {
                eprintln!("Unknown option for translate command: {}", args[i]);
                process::exit(1);
            }
        }
    }

    let arf_file = arf::get_arf_file(false, bytes, descriptor_file.as_deref());
    fs::write(output_file, arf_file.to_bytes()).unwrap_or_else(|_| {
        eprintln!("Failed to write to file: {}", output_file);
        process::exit(1);
    });

    println!("Output written to {}", output_file);
}

fn handle_info(program: &str, args: &[String]) {
    if args.is_empty() {
        eprintln!("Missing input file for info command");
        eprintln!("Usage: {} info <input_file>", program);
        process::exit(1);
    }

    let input_file = &args[0];
    println!("Info for file: {}", input_file);
    let arf_file = ArfFile::from_data(fs::read(input_file).unwrap_or_else(|_| {
        eprintln!("Failed to read file: {}", input_file);
        process::exit(1);
    }));
    arf_file.print_info();
}

fn handle_addlib(program: &str, args: &[String]) {
    if args.is_empty() {
        eprintln!("Missing input file for addlib command");
        eprintln!("Usage: {} addlib <input_file>", program);
        process::exit(1);
    }

    let input_file = &args[0];
    let lib_name = if args.len() > 1 {
        &args[1]
    } else {
        eprintln!("Missing library name for addlib command");
        process::exit(1);
    };
    let lib_path = if args.len() > 2 {
        &args[2]
    } else {
        eprintln!("Missing library path for addlib command");
        process::exit(1);
    };
    let file = fs::read(input_file).unwrap_or_else(|_| {
        eprintln!("Failed to read file: {}", input_file);
        process::exit(1);
    });
    let mut arf_file = ArfFile::from_data(file);

    arf_file.add_library(lib_name, lib_path);

    fs::write(input_file, arf_file.to_bytes()).unwrap_or_else(|_| {
        eprintln!("Failed to write to file: {}", input_file);
        process::exit(1);
    });

    println!("Library {} added to {}", lib_name, input_file);
}
