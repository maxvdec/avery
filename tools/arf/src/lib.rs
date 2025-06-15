use elf::ElfBytes;
use elf::abi;
use elf::abi::DT_NEEDED;
use elf::abi::SHT_REL;
use elf::abi::SHT_RELA;
use elf::endian::AnyEndian;
use phf::phf_map;

const ARF_IDENTIFIER: &str = "ARF003";
const ARL_IDENTIFIER: &str = "ARL003";

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Architecture {
    X86 = 1,
    X86_64 = 2,
    ARMv7 = 3,
    Aarch64 = 4,
}

impl From<Architecture> for u8 {
    fn from(arch: Architecture) -> Self {
        arch as u8
    }
}

impl TryFrom<u8> for Architecture {
    type Error = &'static str;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(Architecture::X86),
            2 => Ok(Architecture::X86_64),
            3 => Ok(Architecture::ARMv7),
            4 => Ok(Architecture::Aarch64),
            _ => Err("Invalid architecture value"),
        }
    }
}

#[derive(Debug)]
pub struct Header {
    version_str: String,
    library: bool,
    architecture: Architecture,
    host_architecture: Architecture,
    entry_point: u32,
}

#[derive(Debug)]
pub struct Section {
    name: String,
    offset: u32,
    permissions: u8,
}

#[derive(Debug)]
pub struct Symbol {
    name: String,
    resolution: u8,
    typ: u8,
    addr: u32,
}

#[derive(Debug)]
pub struct Library {
    name: String,
    availability: u8,
    path: Option<String>,
}

#[derive(Debug)]
pub struct Fix {
    name: String,
    offset: u32,
}

#[derive(Debug)]
pub struct Request {
    byte: u8,
}

#[derive(Debug)]
pub struct ArfFile {
    header: Header,
    sections: Vec<Section>,
    symbols: Vec<Symbol>,
    libraries: Vec<Library>,
    fixes: Vec<Fix>,
    requests: Vec<Request>,
    data: Vec<u8>,
}

#[derive(Debug)]
pub struct ArfDescriptionFile {
    extensions: Vec<u8>,
    library: bool,
}

impl Default for ArfFile {
    fn default() -> Self {
        ArfFile {
            header: Header {
                version_str: String::new(),
                library: false,
                architecture: Architecture::X86,
                host_architecture: Architecture::X86_64,
                entry_point: 0,
            },
            sections: Vec::new(),
            symbols: Vec::new(),
            libraries: Vec::new(),
            fixes: Vec::new(),
            requests: vec![Request { byte: 0x0 }],
            data: Vec::new(),
        }
    }
}

impl ArfFile {
    pub fn to_bytes(self: &ArfFile) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(self.header.version_str.as_bytes());
        bytes.push(self.header.architecture as u8);
        bytes.push(self.header.host_architecture as u8);
        bytes.extend_from_slice(&self.header.entry_point.to_le_bytes());

        // Sections table
        for section in self.sections.iter() {
            bytes.push(0xFF);
            bytes.extend_from_slice(section.name.as_bytes());
            bytes.push(0x00); // Null terminator for section name
            bytes.extend_from_slice(&section.offset.to_le_bytes());
            bytes.push(section.permissions);
        }

        // Symbols table
        for symbol in self.symbols.iter() {
            bytes.push(0xEE);
            bytes.extend_from_slice(symbol.name.as_bytes());
            bytes.push(0x00); // Null terminator for symbol name
            bytes.push(symbol.resolution);
            bytes.push(symbol.typ);
            bytes.extend_from_slice(&symbol.addr.to_le_bytes());
        }

        // Libraries table
        for library in self.libraries.iter() {
            bytes.push(0xDD);
            bytes.extend_from_slice(library.name.as_bytes());
            bytes.push(0x00); // Null terminator for library name
            bytes.push(library.availability);
        }

        // Fixes table
        for fix in self.fixes.iter() {
            bytes.push(0xCC);
            bytes.extend_from_slice(fix.name.as_bytes());
            bytes.push(0x00); // Null terminator for fix name
            bytes.extend_from_slice(&fix.offset.to_le_bytes());
        }

        bytes.push(0xBB);
        // Requests table
        for request in self.requests.iter() {
            bytes.push(request.byte);
        }

        // Data section
        bytes.push(0xFF);
        bytes.extend_from_slice(&self.data);
        return bytes;
    }

    pub fn from_data(data: Vec<u8>) -> Self {
        let mut arf_file = ArfFile::default();
        let mut offset = 0;

        // Read header
        arf_file.header.version_str = String::from_utf8(data[offset..offset + 6].to_vec()).unwrap();
        offset += 6;
        arf_file.header.architecture = Architecture::try_from(data[offset]).unwrap();
        offset += 1;
        arf_file.header.host_architecture = Architecture::try_from(data[offset]).unwrap();
        offset += 1;
        arf_file.header.entry_point =
            u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap());
        offset += 4;

        // Read sections
        while data[offset] == 0xFF {
            offset += 1; // Skip section type byte
            let name_end = data[offset..].iter().position(|&b| b == 0).unwrap() + offset;
            let name = String::from_utf8(data[offset..name_end].to_vec()).unwrap();
            offset = name_end + 1; // Skip null terminator
            let section_offset = u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap());
            offset += 4;
            let permissions = data[offset];
            offset += 1;

            arf_file.sections.push(Section {
                name,
                offset: section_offset,
                permissions,
            });
        }

        while data[offset] == 0xEE {
            offset += 1; // Skip symbol type byte
            let name_end = data[offset..].iter().position(|&b| b == 0).unwrap() + offset;
            let name = String::from_utf8(data[offset..name_end].to_vec()).unwrap();
            offset = name_end + 1; // Skip null terminator
            let resolution = data[offset];
            offset += 1;
            let typ = data[offset];
            offset += 1;
            let addr = u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap());
            offset += 4;

            arf_file.symbols.push(Symbol {
                name,
                resolution,
                typ,
                addr,
            });
        }

        while data[offset] == 0xDD {
            offset += 1; // Skip library type byte
            let name_end = data[offset..].iter().position(|&b| b == 0).unwrap() + offset;
            let name = String::from_utf8(data[offset..name_end].to_vec()).unwrap();
            offset = name_end + 1; // Skip null terminator
            let availability = data[offset];
            offset += 1;

            let mut path = None;
            if availability == 0xFF {
                let path_end = data[offset..].iter().position(|&b| b == 0).unwrap() + offset;
                path = if path_end > offset {
                    Some(String::from_utf8(data[offset..path_end].to_vec()).unwrap())
                } else {
                    None
                };
                offset = path_end + 1; // Skip null terminator
            }

            arf_file.libraries.push(Library {
                name,
                availability,
                path,
            });
        }

        while data[offset] == 0xCC {
            offset += 1; // Skip fix type byte
            let name_end = data[offset..].iter().position(|&b| b == 0).unwrap() + offset;
            let name = String::from_utf8(data[offset..name_end].to_vec()).unwrap();
            offset = name_end + 1; // Skip null terminator
            let fix_offset = u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap());
            offset += 4;

            arf_file.fixes.push(Fix {
                name,
                offset: fix_offset,
            });
        }

        if data[offset] == 0xBB {
            offset += 1;
        }
        while data[offset] != 0xFF {
            println!("Request byte: {:02X}", data[offset]);
            arf_file.requests.push(Request { byte: data[offset] });
            offset += 1;
        }

        offset += 1; // Skip data type byte
        let data_start = offset;
        let data_end = data[data_start..]
            .iter()
            .position(|&b| b == 0xFF)
            .unwrap_or(data.len() - data_start)
            + data_start;
        arf_file.data = data[data_start..data_end].to_vec();
        offset = data_end;
        if offset < data.len() {
            panic!("Unexpected data after ARF file content");
        }
        arf_file.header.library = arf_file.header.version_str.starts_with("ARL");
        arf_file.header.version_str = if arf_file.header.library {
            ARL_IDENTIFIER.to_string()
        } else {
            ARF_IDENTIFIER.to_string()
        };

        return arf_file;
    }

    pub fn print_info(self: &ArfFile) {
        println!("ARF File Info:");
        println!("Version: {}", self.header.version_str);
        println!("Library: {}", self.header.library);
        println!("Architecture: {:?}", self.header.architecture);
        println!("Host Architecture: {:?}", self.header.host_architecture);
        println!("Entry Point: 0x{:X}", self.header.entry_point);

        println!("\nSections:");
        for section in &self.sections {
            println!(
                "  Name: {}, Offset: 0x{:X}, Permissions: {:02X}",
                section.name, section.offset, section.permissions
            );
        }

        println!("\nSymbols:");
        for symbol in &self.symbols {
            println!(
                "  Name: {}, Resolution: {}, Type: {}, Address: 0x{:X}",
                symbol.name, symbol.resolution, symbol.typ, symbol.addr
            );
        }

        println!("\nLibraries:");
        for library in &self.libraries {
            println!(
                "  Name: {}, Availability: {}, Path: {:?}",
                library.name, library.availability, library.path
            );
        }

        println!("\nFixes:");
        for fix in &self.fixes {
            println!("  Name: {}, Offset: 0x{:X}", fix.name, fix.offset);
        }

        println!("\nRequests:");
        for request in &self.requests {
            println!(
                "  Extension: {}",
                EXTENSIONS
                    .entries()
                    .find_map(|(key, &val)| if val == request.byte { Some(key) } else { None })
                    .unwrap_or(&"unknown")
            );
        }

        println!("\nData Size: {} bytes", self.data.len());
    }

    pub fn add_library(&mut self, name: &str, path: &str) {
        self.libraries.push(Library {
            name: name.to_string(),
            availability: 0xFF, // Assuming 0xFF means available
            path: Some(path.to_string()),
        });
    }
}

pub fn get_arf_file(library: bool, bytes: Vec<u8>, descriptor_file: Option<&str>) -> ArfFile {
    let mut arf_file = ArfFile::default();
    if !library {
        arf_file.header.version_str = ARF_IDENTIFIER.to_string();
        arf_file.header.library = false;
    } else {
        arf_file.header.version_str = ARL_IDENTIFIER.to_string();
        arf_file.header.library = true;
    }

    let elf = ElfBytes::<elf::endian::AnyEndian>::minimal_parse(&bytes).unwrap();
    arf_file.header.architecture = match elf.ehdr.e_machine {
        abi::EM_X86_64 => Architecture::X86_64,
        abi::EM_386 => Architecture::X86,
        abi::EM_ARM => Architecture::ARMv7,
        abi::EM_AARCH64 => Architecture::Aarch64,
        _ => panic!("Unsupported architecture"),
    };
    arf_file.header.host_architecture = match std::env::consts::ARCH {
        "x86_64" => Architecture::X86_64,
        "x86" => Architecture::X86,
        "arm" => Architecture::ARMv7,
        "aarch64" => Architecture::Aarch64,
        _ => panic!("Unsupported host architecture"),
    };
    arf_file.header.entry_point = elf.ehdr.e_entry as u32;

    arf_file.sections = get_sections_table(&elf);
    arf_file.symbols = get_symbols(&elf, &arf_file);
    arf_file.libraries = get_libraries(&elf);
    arf_file.fixes = get_fixes(&elf);
    arf_file.data = extract_section_data(&elf);

    if descriptor_file.is_some() {
        arf_file.requests = parse_ad_file(descriptor_file.unwrap())
            .extensions
            .iter()
            .map(|&ext| Request { byte: ext })
            .collect();
        arf_file.header.library = parse_ad_file(descriptor_file.unwrap()).library;
        if arf_file.header.library {
            arf_file.header.version_str = ARL_IDENTIFIER.to_string();
        } else {
            arf_file.header.version_str = ARF_IDENTIFIER.to_string();
        }
    }

    return arf_file;
}

static EXTENSIONS: phf::Map<&'static str, u8> = phf_map! {
    "console" => 0x00,
    "framebuffer" => 0x01,
    "filesystem" => 0x02,
};

pub fn parse_ad_file(file_path: &str) -> ArfDescriptionFile {
    let str = std::fs::read_to_string(file_path)
        .unwrap_or_else(|_| panic!("Failed to read file: {}", file_path));
    let mut extensions = Vec::new();
    let mut library = false;
    for line in str.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with(';') || line == "[kernextensions]" {
            continue;
        }
        if line == "[library]" {
            library = true;
            continue;
        }
        if let Some(&ext) = EXTENSIONS.get(line) {
            extensions.push(ext);
        } else {
            panic!("Unknown extension: {}", line);
        }
    }

    return ArfDescriptionFile {
        extensions,
        library,
    };
}

pub fn get_sections_table(elf: &ElfBytes<'_, AnyEndian>) -> Vec<Section> {
    let (section_headers, sections_names) = elf.section_headers_with_strtab().unwrap();

    let mut sections: Vec<Section> = Vec::new();

    for section_header in section_headers.unwrap() {
        let name = sections_names
            .unwrap()
            .get(section_header.sh_name as usize)
            .unwrap_or("<no name>");
        if sections.iter().any(|s| s.name == name) || name.is_empty() {
            continue;
        }

        let mut perms = 0u8;
        let flags = section_header.sh_flags;

        if flags & abi::SHF_ALLOC as u64 != 0 {
            perms |= 0x00; // Allocated
        }
        if flags & abi::SHF_EXECINSTR as u64 != 0 {
            perms |= 0x04; // Executable
        }
        if flags & abi::SHF_WRITE as u64 != 0 {
            perms |= 0x0; // Writable
        }

        let known_mask = abi::SHF_ALLOC | abi::SHF_WRITE | abi::SHF_EXECINSTR;
        if flags & !known_mask as u64 != 0 {
            perms |= 0x10;
        }

        sections.push(Section {
            name: name.to_string(),
            offset: section_header.sh_addr as u32,
            permissions: perms,
        });
    }

    return sections;
}

pub fn get_symbols(elf: &ElfBytes<'_, AnyEndian>, executable: &ArfFile) -> Vec<Symbol> {
    let (symbol_table, symbol_str) = elf.symbol_table().unwrap().unwrap();

    let mut symbols_vec: Vec<Symbol> = Vec::new();

    for symbol in symbol_table {
        let name = symbol_str
            .get(symbol.st_name as usize)
            .unwrap_or("<no name>");

        if symbols_vec.iter().any(|s| s.name == name) || name.is_empty() {
            continue;
        }

        let binding = symbol.st_bind();
        let symbol_typ = match binding {
            elf::abi::STB_LOCAL => 0,
            elf::abi::STB_GLOBAL => 1,
            elf::abi::STB_WEAK => 2,
            _ => continue, // STB_LOOS, STB_HIOS, etc.
        };

        let resolution = match symbol.st_shndx {
            elf::abi::SHN_UNDEF => 1,
            elf::abi::SHN_COMMON => 2,
            _ => 0,
        };

        let (_, sections_str) = elf.section_headers_with_strtab().unwrap();
        let string_ind = symbol.st_shndx as usize;
        let str = sections_str
            .unwrap()
            .get(string_ind)
            .unwrap_or("<no section>");
        let section_offset = if str.is_empty() {
            0
        } else {
            executable
                .sections
                .iter()
                .find(|s| s.name == str)
                .map_or(0, |s| s.offset)
        };

        symbols_vec.push(Symbol {
            name: name.to_string(),
            resolution,
            typ: symbol_typ,
            addr: (symbol.st_value as u32) + section_offset,
        });
    }

    return symbols_vec;
}

fn get_libraries(elf: &ElfBytes<AnyEndian>) -> Vec<Library> {
    let mut libraries = Vec::new();

    let section_headers = elf
        .section_headers()
        .ok_or("No section headers found")
        .unwrap();
    let section_header_strtab = elf.section_headers_with_strtab().unwrap();

    let mut dynamic_section = None;
    let mut dynstr_section = None;

    for (_, shdr) in section_headers.iter().enumerate() {
        if let Ok(name) = section_header_strtab.1.unwrap().get(shdr.sh_name as usize) {
            match name {
                ".dynamic" => dynamic_section = Some(shdr),
                ".dynstr" => dynstr_section = Some(shdr),
                _ => {}
            }
        }
    }

    if let (Some(dynamic_shdr), Some(dynstr_shdr)) = (dynamic_section, dynstr_section) {
        let dynamic_data = elf.section_data(&dynamic_shdr).unwrap();
        let dynstr_data = elf.section_data(&dynstr_shdr).unwrap();

        let dynamic_table =
            elf::dynamic::DynamicTable::new(elf.ehdr.endianness, elf.ehdr.class, dynamic_data.0);
        let dynamic_entries = dynamic_table.iter();

        for entry_result in dynamic_entries {
            let entry = entry_result;
            if entry.d_tag == DT_NEEDED {
                let str_offset = entry.d_val() as usize;
                let lib_name = extract_string_from_table(dynstr_data.0, str_offset).unwrap();
                if !lib_name.is_empty() {
                    libraries.push(Library {
                        name: lib_name,
                        availability: 0,
                        path: None,
                    });
                }
            }
        }
    }

    return libraries;
}

fn extract_string_from_table(
    strtab_data: &[u8],
    offset: usize,
) -> Result<String, Box<dyn std::error::Error>> {
    if offset >= strtab_data.len() {
        return Err("String offset out of bounds".into());
    }

    let mut end = offset;
    while end < strtab_data.len() && strtab_data[end] != 0 {
        end += 1;
    }

    let string_bytes = &strtab_data[offset..end];
    Ok(String::from_utf8(string_bytes.to_vec())?)
}

fn get_fixes(elf: &ElfBytes<AnyEndian>) -> Vec<Fix> {
    let mut fixes = Vec::new();

    let section_headers = elf.section_headers().unwrap();

    let (symbol_table, symbol_str) = match elf.symbol_table() {
        Ok(Some((table, strings))) => (table, strings),
        _ => return fixes,
    };

    for section_header in section_headers {
        match section_header.sh_type {
            SHT_REL => {
                if let Ok(section_data) = elf.section_data(&section_header) {
                    let rel_entries = elf::relocation::RelIterator::new(
                        elf.ehdr.endianness,
                        elf.ehdr.class,
                        section_data.0,
                    );

                    for rel in rel_entries {
                        let symbol_index = rel.r_sym as usize;

                        if let Ok(symbol) = symbol_table.get(symbol_index) {
                            let symbol_name = symbol_str
                                .get(symbol.st_name as usize)
                                .unwrap_or("<unknown>");

                            if symbol.st_shndx == elf::abi::SHN_UNDEF && !symbol_name.is_empty() {
                                fixes.push(Fix {
                                    name: symbol_name.to_string(),
                                    offset: rel.r_offset as u32,
                                });
                            }
                        }
                    }
                }
            }
            SHT_RELA => {
                if let Ok(section_data) = elf.section_data(&section_header) {
                    let rela_entries = elf::relocation::RelaIterator::new(
                        elf.ehdr.endianness,
                        elf.ehdr.class,
                        section_data.0,
                    );

                    for rela in rela_entries {
                        let symbol_index = rela.r_sym as usize;

                        if let Ok(symbol) = symbol_table.get(symbol_index) {
                            let symbol_name = symbol_str
                                .get(symbol.st_name as usize)
                                .unwrap_or("<unknown>");

                            if symbol.st_shndx == elf::abi::SHN_UNDEF && !symbol_name.is_empty() {
                                fixes.push(Fix {
                                    name: symbol_name.to_string(),
                                    offset: rela.r_offset as u32,
                                });
                            }
                        }
                    }
                }
            }
            _ => continue,
        }
    }

    fixes.sort_by(|a, b| a.name.cmp(&b.name).then(a.offset.cmp(&b.offset)));
    fixes.dedup_by(|a, b| a.name == b.name && a.offset == b.offset);

    fixes
}

pub fn extract_section_data(elf: &ElfBytes<AnyEndian>) -> Vec<u8> {
    let mut data = Vec::new();
    let section_headers = elf.section_headers().unwrap();
    let (_, section_names) = match elf.section_headers_with_strtab() {
        Ok((headers, names)) => (headers, names),
        Err(_) => return data,
    };

    let mut sections_with_data = Vec::new();

    let mut min_vaddr = u64::MAX;
    let mut has_loadable_sections = false;

    for section_header in section_headers.iter() {
        if section_header.sh_flags & abi::SHF_ALLOC as u64 == 0 {
            continue;
        }

        if section_header.sh_type == abi::SHT_NOBITS {
            continue;
        }

        if section_header.sh_size == 0 {
            continue;
        }

        let section_name = section_names
            .map(|names| {
                names
                    .get(section_header.sh_name as usize)
                    .unwrap_or("<unknown>")
            })
            .unwrap_or("<unknown>");

        if section_name.starts_with(".debug")
            || section_name.starts_with(".comment")
            || section_name == ".shstrtab"
            || section_name == ".strtab"
            || section_name == ".symtab"
        {
            continue;
        }

        if section_header.sh_addr < min_vaddr {
            min_vaddr = section_header.sh_addr;
            has_loadable_sections = true;
        }

        if let Ok(section_data) = elf.section_data(&section_header) {
            sections_with_data.push((section_header, section_data.0, section_name));
        }
    }

    if !has_loadable_sections {
        println!("No loadable sections found");
        return data;
    }

    sections_with_data.sort_by_key(|(header, _, _)| header.sh_addr);

    let mut current_file_offset = 0usize;

    for (section_header, section_data, section_name) in sections_with_data {
        let vaddr_offset = (section_header.sh_addr - min_vaddr) as usize;

        if vaddr_offset > current_file_offset {
            let gap_size = vaddr_offset - current_file_offset;
            data.extend(vec![0u8; gap_size]);
            current_file_offset = vaddr_offset;
        } else if vaddr_offset < current_file_offset {
            println!(
                "Warning: Section {} overlaps previous data (vaddr_offset: 0x{:X}, current_offset: 0x{:X})",
                section_name, vaddr_offset, current_file_offset
            );
        }

        match section_header.sh_type {
            abi::SHT_NOBITS => {
                println!("Warning: Encountered SHT_NOBITS section in data extraction");
                data.extend(vec![0u8; section_header.sh_size as usize]);
            }
            _ => {
                data.extend_from_slice(section_data);

                if section_header.sh_size as usize > section_data.len() {
                    let extra_zeros = section_header.sh_size as usize - section_data.len();
                    data.extend(vec![0u8; extra_zeros]);
                }
            }
        }

        current_file_offset += section_header.sh_size as usize;
    }

    align_data(&mut data, 16);

    println!("Total extracted data size: {} bytes", data.len());
    data
}

fn align_data(data: &mut Vec<u8>, alignment: usize) {
    let remainder = data.len() % alignment;
    if remainder != 0 {
        let padding = alignment - remainder;
        data.extend(vec![0u8; padding]);
    }
}

pub fn write_arf_file(file_path: &str, arf_file: &ArfFile) -> std::io::Result<()> {
    let bytes = arf_file.to_bytes();
    std::fs::write(file_path, bytes)?;
    Ok(())
}
