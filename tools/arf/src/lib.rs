use elf::ElfBytes;
use elf::abi;
use elf::abi::DT_NEEDED;
use elf::abi::SHT_REL;
use elf::abi::SHT_RELA;
use elf::endian::AnyEndian;
use phf::phf_map;

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Architecture {
    X86 = 0,
    X86_64 = 1,
    ARMv7 = 2,
    Aarch64 = 3,
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
            0 => Ok(Architecture::X86),
            1 => Ok(Architecture::X86_64),
            2 => Ok(Architecture::ARMv7),
            3 => Ok(Architecture::Aarch64),
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
            requests: Vec::new(),
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

        // Requests table
        for request in self.requests.iter() {
            bytes.push(0xBB);
            bytes.push(request.byte);
        }

        // Data section
        bytes.push(0xFF);
        bytes.extend_from_slice(&self.data);
        return bytes;
    }
}

pub fn get_arf_file(library: bool, bytes: Vec<u8>, descriptor_file: Option<&str>) -> ArfFile {
    let mut arf_file = ArfFile::default();
    if !library {
        arf_file.header.version_str = "ARF001".to_string();
        arf_file.header.library = false;
    } else {
        arf_file.header.version_str = "ARL001".to_string();
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
    arf_file.symbols = get_symbols(&elf);
    arf_file.libraries = get_libraries(&elf);
    arf_file.fixes = get_fixes(&elf);
    arf_file.data = extract_section_data(&elf);

    if descriptor_file.is_some() {
        arf_file.requests = parse_ad_file(descriptor_file.unwrap())
            .extensions
            .iter()
            .map(|&ext| Request { byte: ext })
            .collect();
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
    for line in str.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with(';') || line == "[kernextensions]" {
            continue;
        }
        if let Some(&ext) = EXTENSIONS.get(line) {
            extensions.push(ext);
        } else {
            panic!("Unknown extension: {}", line);
        }
    }

    return ArfDescriptionFile { extensions };
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
            offset: section_header.sh_offset as u32,
            permissions: perms,
        });
    }

    return sections;
}

pub fn get_symbols(elf: &ElfBytes<'_, AnyEndian>) -> Vec<Symbol> {
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

        symbols_vec.push(Symbol {
            name: name.to_string(),
            resolution: resolution,
            typ: symbol_typ,
            addr: symbol.st_value as u32,
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

    for section_header in section_headers {
        if section_header.sh_flags & abi::SHF_ALLOC as u64 == 0 {
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

        if let Ok(section_data) = elf.section_data(&section_header) {
            sections_with_data.push((section_header, section_data.0, section_name));
        }
    }

    sections_with_data.sort_by_key(|(header, _, _)| header.sh_addr);

    let mut current_offset = 0u64;
    let mut base_address = 0u64;
    let mut first_section = true;

    for (section_header, section_data, _) in sections_with_data {
        if first_section {
            base_address = section_header.sh_addr;
            first_section = false;
        }

        let expected_offset = section_header.sh_addr - base_address;

        if expected_offset > current_offset {
            let gap_size = (expected_offset - current_offset) as usize;
            data.extend(vec![0u8; gap_size]);
            current_offset = expected_offset;
        }

        let alignment = if section_header.sh_addralign > 0 {
            section_header.sh_addralign
        } else {
            1
        };

        let misalignment = current_offset % alignment;
        if misalignment != 0 {
            let padding = alignment - misalignment;
            data.extend(vec![0u8; padding as usize]);
            current_offset += padding;
        }

        match section_header.sh_type {
            abi::SHT_NOBITS => {
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

        current_offset += section_header.sh_size;
    }

    align_data(&mut data, 16);

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
