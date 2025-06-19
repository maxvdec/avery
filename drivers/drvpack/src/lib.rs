struct DriverFile {
    header: String,
    type_byte: u8,
    manufacturer: u16,
    device_id: u16,
    subsystem: u8,

    driver_name: String,
    driver_description: String,
    driver_version: [u8; 3],

    hash: String,

    exec: Vec<u8>,
}

impl Default for DriverFile {
    fn default() -> Self {
        Self {
            header: HEADER.to_string(),
            type_byte: 0,
            manufacturer: 0,
            device_id: 0,
            subsystem: 0,

            driver_name: String::new(),
            driver_description: String::new(),
            driver_version: [0; 3],

            hash: String::new(),

            exec: String::new(),
        }
    }
}

impl DriverFile {
    pub fn set_options(&mut self, options: Options) {
        self.header = HEADER.to_string();
        self.type_byte = options.driver_type();
        self.manufacturer = options.manufacturer();
        self.device_id = options.device_id();
        self.subsystem = options.subsystem();

        self.driver_name = options.driver_name().to_string();
        self.driver_description = options.driver_description().to_string();
        self.driver_version = options.driver_version();

        self.hash = String::new();

        self.exec = String::new();
    }
}

const HEADER: &str = "AVDRIV01";

pub struct Options {
    driver_name: String,
    driver_description: String,
    driver_version: [u8; 3],
    manufacturer: u16,
    device_id: u16,
    subsystem: u8,
    driver_type: u8,
}

impl Options {
    pub fn driver_name(&self) -> &str {
        &self.driver_name
    }

    pub fn driver_description(&self) -> &str {
        &self.driver_description
    }

    pub fn driver_version(&self) -> [u8; 3] {
        self.driver_version
    }

    pub fn manufacturer(&self) -> u16 {
        self.manufacturer
    }

    pub fn device_id(&self) -> u16 {
        self.device_id
    }

    pub fn subsystem(&self) -> u8 {
        self.subsystem
    }

    pub fn driver_type(&self) -> u8 {
        self.driver_type
    }
}

pub fn get_options() -> Options {
    use std::io::{self, Write};

    println!("Welcome to the Avery System Driver Packer.");
    println!(
        "We'll ask you some questions in order to determine and pack the driver with the corresponding flags.\n"
    );

    print!("- What's the name of your driver?\n> ");
    io::stdout().flush().unwrap();
    let mut input = String::new();
    io::stdin().read_line(&mut input).unwrap();
    let driver_name = input.trim().to_string();

    print!("\n- Describe your driver in a sentence\n> ");
    io::stdout().flush().unwrap();
    input.clear();
    io::stdin().read_line(&mut input).unwrap();
    let driver_description = input.trim().to_string();

    print!("\n- What version is your driver in?\n> ");
    io::stdout().flush().unwrap();
    input.clear();
    io::stdin().read_line(&mut input).unwrap();
    let version_str = input.trim();
    let version_parts: Vec<&str> = version_str.split('.').collect();
    let driver_version = [
        version_parts.get(0).unwrap_or(&"1").parse().unwrap_or(1),
        version_parts.get(1).unwrap_or(&"0").parse().unwrap_or(0),
        version_parts.get(2).unwrap_or(&"0").parse().unwrap_or(0),
    ];

    print!("\n- Introduce the manufacturer ID (default 0x0)\n> ");
    io::stdout().flush().unwrap();
    input.clear();
    io::stdin().read_line(&mut input).unwrap();
    let manufacturer = if input.trim().is_empty() {
        println!("(using 0x0)");
        0x0
    } else {
        let trimmed = input.trim();
        if trimmed.starts_with("0x") {
            u16::from_str_radix(&trimmed[2..], 16).unwrap_or(0x0)
        } else {
            trimmed.parse().unwrap_or(0x0)
        }
    };

    print!("\n- Introduce the device ID (default 0x0)\n> ");
    io::stdout().flush().unwrap();
    input.clear();
    io::stdin().read_line(&mut input).unwrap();
    let device_id = if input.trim().is_empty() {
        println!("(using 0x0)");
        0x0
    } else {
        let trimmed = input.trim();
        if trimmed.starts_with("0x") {
            u16::from_str_radix(&trimmed[2..], 16).unwrap_or(0x0)
        } else {
            trimmed.parse().unwrap_or(0x0)
        }
    };

    print!("\n- Introduce the subsystem ID (default 0x0)\n> ");
    io::stdout().flush().unwrap();
    input.clear();
    io::stdin().read_line(&mut input).unwrap();
    let subsystem = if input.trim().is_empty() {
        println!("(using 0x0)");
        0x0
    } else {
        let trimmed = input.trim();
        if trimmed.starts_with("0x") {
            u8::from_str_radix(&trimmed[2..], 16).unwrap_or(0x0)
        } else {
            trimmed.parse().unwrap_or(0x0)
        }
    };

    print!("\n- Type in the type ID (default 'Empty Driver (0)')\n> ");
    io::stdout().flush().unwrap();
    input.clear();
    io::stdin().read_line(&mut input).unwrap();
    let driver_type = if input.trim().is_empty() {
        0
    } else {
        input.trim().parse().unwrap_or(0)
    };

    println!("\nPacking driver...\n");

    Options {
        driver_name,
        driver_description,
        driver_version,
        manufacturer,
        device_id,
        subsystem,
        driver_type,
    }
}

pub fn get_driver_file(executable: String) -> DriverFile {
    let options = get_options();
    let mut driver_file = DriverFile::default();

    driver_file.set_options(options);

    let executable_contents = std::fs::read(executable).unwrap();

    driver_file.exec = executable_contents;

    let mut hashed_bytes = Vec::new();
    hashed_bytes.extend_from_slice(driver_file.driver_name.as_bytes());
    hashed_bytes.extend_from_slice(&driver_file.manufacturer.to_le_bytes());
    hashed_bytes.extend_from_slice(&driver_file.exec);

    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(&hashed_bytes);
    let hash_result = hasher.finalize();
    driver_file.hash = format!("{:x}", hash_result);

    driver_file
}
