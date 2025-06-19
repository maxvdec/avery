use drvpack::get_driver_file;

fn main() {
    use std::env;
    use std::process;

    let args: Vec<String> = env::args().collect();

    if args.len() < 3 {
        eprintln!(
            "Usage: {} <input_file> -o <output_file> [-d <description_file>]",
            args[0]
        );
        process::exit(1);
    }

    let input_file = &args[1];
    let mut output_file = String::new();
    let mut description_file: Option<String> = None;

    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "-o" => {
                if i + 1 < args.len() {
                    output_file = args[i + 1].clone();
                    i += 2;
                } else {
                    eprintln!("Error: -o flag requires an output file");
                    process::exit(1);
                }
            }
            "-d" => {
                if i + 1 < args.len() {
                    description_file = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    eprintln!("Error: -d flag requires a description file");
                    process::exit(1);
                }
            }
            _ => {
                eprintln!("Error: Unknown flag {}", args[i]);
                process::exit(1);
            }
        }
    }

    if output_file.is_empty() {
        eprintln!("Error: -o flag with output file is required");
        process::exit(1);
    }

    let driver = get_driver_file(input_file.clone(), description_file);
    let bytes = driver.to_bytes();
    let _ = std::fs::write(&output_file, bytes);
}
