fn main() {
    let args = std::env::args().collect::<Vec<String>>();

    if args.len() < 2 {
        eprintln!(
            "Usage: {} <input_file> [-o output_file] [-d descriptor_file]",
            args[0]
        );
        std::process::exit(1);
    }

    let input_file = &args[1];
    let bytes = std::fs::read(input_file).unwrap_or_else(|_| {
        eprintln!("Failed to read file: {}", input_file);
        std::process::exit(1);
    });

    let mut output_file = "out.arf";
    let mut descriptor_file: Option<String> = None;

    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "-o" => {
                if i + 1 < args.len() {
                    output_file = &args[i + 1];
                    i += 2;
                } else {
                    eprintln!("Missing output file path after -o");
                    std::process::exit(1);
                }
            }
            "-d" => {
                if i + 1 < args.len() {
                    descriptor_file = Some(args[i + 1].clone());
                    i += 2;
                } else {
                    eprintln!("Missing descriptor file path after -d");
                    std::process::exit(1);
                }
            }
            _ => {
                eprintln!("Unknown option: {}", args[i]);
                std::process::exit(1);
            }
        }
    }

    let arf_file = arf::get_arf_file(false, bytes, descriptor_file.as_deref());
    std::fs::write(output_file, arf_file.to_bytes()).unwrap_or_else(|_| {
        eprintln!("Failed to write to file: {}", output_file);
        std::process::exit(1);
    });

    println!("Output written to {}", output_file);
}
