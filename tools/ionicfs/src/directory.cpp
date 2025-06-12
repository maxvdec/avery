#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>

namespace fs = std::filesystem;

Directory parseRootDirectory(const fs::path &diskPath, int partitionIndex) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return {};
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return {};
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return {};
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return {};
    }

    DriveInformation info = getDriveInformation(diskPath).value();
    if (partitionIndex < 0 || partitionIndex >= 4) {
        std::cerr << "Error: Invalid partition index." << std::endl;
        return {};
    }
    Partition partition = info.partitions[partitionIndex];
    if (!partition.usable) {
        std::cerr << "Error: Partition is not usable." << std::endl;
        return {};
    }

    return parseDirectory(diskPath, partition.partitionRegion);
}

Directory parseDirectory(const fs::path &diskPath, uint32_t region) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return {};
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return {};
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return {};
    }

    std::fstream diskFile(diskPath, std::ios::in | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return {};
    }

    std::vector<DirectoryEntry> entries;
    uint32_t currentRegion = region;

    while (currentRegion != 0) {
        char regionData[512] = {0};
        diskFile.seekp(currentRegion * 512);
        diskFile.read(regionData, sizeof(regionData));

        if (!diskFile) {
            std::cerr << "Error: Failed to read region " << currentRegion
                      << std::endl;
            break;
        }

        if (regionData[0] != DIRECTORY_REGION) {
            std::cerr << "Error: Region " << currentRegion
                      << " is not a directory region (type: "
                      << static_cast<int>(regionData[0]) << ")" << std::endl;
            break;
        }

        int offset = 1;

        while (offset < 508) {
            if (offset + 25 > 508) {
                break;
            }

            char entryType = regionData[offset];

            if (entryType == 0x0) {
                break;
            }

            if (entryType == 0x1) {
                offset++;
                continue;
            }

            if (entryType != 0x2 && entryType != 0x3) {
                std::cerr << "Warning: Unknown entry type "
                          << static_cast<int>(entryType) << " at offset "
                          << offset << std::endl;
                offset++;
                continue;
            }

            DirectoryEntry entry;
            entry.isDirectory = (entryType == 0x2);
            offset += 1;

            entry.lastAccessed = 0;
            for (int i = 0; i < 8; i++) {
                entry.lastAccessed |=
                    (static_cast<uint64_t>(
                         static_cast<uint8_t>(regionData[offset + i]))
                     << (i * 8));
            }
            offset += 8;

            entry.lastModified = 0;
            for (int i = 0; i < 8; i++) {
                entry.lastModified |=
                    (static_cast<uint64_t>(
                         static_cast<uint8_t>(regionData[offset + i]))
                     << (i * 8));
            }
            offset += 8;

            entry.created = 0;
            for (int i = 0; i < 8; i++) {
                entry.created |= (static_cast<uint64_t>(static_cast<uint8_t>(
                                      regionData[offset + i]))
                                  << (i * 8));
            }
            offset += 8;

            entry.name.clear();
            while (offset < 508 && regionData[offset] != '\0') {
                entry.name += regionData[offset];
                offset++;
            }

            if (offset >= 508) {
                std::cerr << "Error: Filename extends beyond region boundary"
                          << std::endl;
                break;
            }

            offset++;

            if (offset + 4 > 508) {
                std::cerr << "Error: Not enough space for region number"
                          << std::endl;
                break;
            }

            entry.region = static_cast<uint32_t>(
                               static_cast<uint8_t>(regionData[offset])) |
                           (static_cast<uint32_t>(
                                static_cast<uint8_t>(regionData[offset + 1]))
                            << 8) |
                           (static_cast<uint32_t>(
                                static_cast<uint8_t>(regionData[offset + 2]))
                            << 16) |
                           (static_cast<uint32_t>(
                                static_cast<uint8_t>(regionData[offset + 3]))
                            << 24);
            offset += 4;

            entries.push_back(entry);
        }

        currentRegion =
            static_cast<uint32_t>(static_cast<uint8_t>(regionData[508])) |
            (static_cast<uint32_t>(static_cast<uint8_t>(regionData[509]))
             << 8) |
            (static_cast<uint32_t>(static_cast<uint8_t>(regionData[510]))
             << 16) |
            (static_cast<uint32_t>(static_cast<uint8_t>(regionData[511]))
             << 24);
    }

    return {region, entries};
}

uint32_t traverseDirectory(const fs::path &diskPath,
                           const std::string &directoryName,
                           int partitionIndex) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return 0;
    }
    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return 0;
    }
    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return 0;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return 0;
    }

    DriveInformation info = getDriveInformation(diskPath).value();
    if (partitionIndex < 0 || partitionIndex >= 4) {
        std::cerr << "Error: Invalid partition index." << std::endl;
        return 0;
    }

    Partition partition = info.partitions[partitionIndex];
    if (!partition.usable) {
        std::cerr << "Error: Partition is not usable." << std::endl;
        return 0;
    }

    if (directoryName.empty()) {
        auto rootDir = parseRootDirectory(diskPath, partitionIndex);
        return rootDir.region;
    }

    auto rootResult = parseRootDirectory(diskPath, partitionIndex);
    std::vector<DirectoryEntry> entries = rootResult.entries;
    uint32_t currentRegion = rootResult.region;

    std::vector<std::string> pathItems;
    std::string path = directoryName;

    if (path.substr(0, 2) == "./") {
        path = path.substr(2);
    }

    std::string delimiter = "/";
    size_t pos = 0;
    while ((pos = path.find(delimiter)) != std::string::npos) {
        std::string token = path.substr(0, pos);
        if (!token.empty()) {
            pathItems.push_back(token);
        }
        path.erase(0, pos + delimiter.length());
    }
    if (!path.empty()) {
        pathItems.push_back(path);
    }

    if (pathItems.empty()) {
        return currentRegion;
    }

    for (size_t i = 0; i < pathItems.size(); i++) {
        const std::string &currentPath = pathItems[i];

        if (currentPath == ".") {
            continue;
        }

        bool foundEntry = false;
        for (const auto &entry : entries) {
            if (entry.name == currentPath && entry.isDirectory) {
                foundEntry = true;
                currentRegion = entry.region;

                uint32_t maxRegions = partition.partitionSize;
                if (currentRegion >= maxRegions || currentRegion == 0) {
                    std::cerr << "Error: Invalid region number "
                              << currentRegion << " (max: " << maxRegions << ")"
                              << std::endl;
                    return 0;
                }

                auto dirResult = parseDirectory(diskPath, currentRegion);
                entries = dirResult.entries;
                break;
            }
        }

        if (!foundEntry) {
            std::cerr << "Error: Directory '" << currentPath
                      << "' not found in current location." << std::endl;
            return 0;
        }
    }

    return currentRegion;
}

void createDirectory(const fs::path &diskPath, const std::string &dirName,
                     int partitionIndex) {

    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return;
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return;
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return;
    }

    DriveInformation info = getDriveInformation(diskPath).value();
    if (partitionIndex < 0 || partitionIndex >= 4) {
        std::cerr << "Error: Invalid partition index." << std::endl;
        return;
    }
    Partition partition = info.partitions[partitionIndex];
    if (!partition.usable) {
        std::cerr << "Error: Partition is not usable." << std::endl;
        return;
    }

    std::string withoutLastComponent;
    std::string directoryName;

    size_t lastSlash = dirName.find_last_of('/');
    if (lastSlash == std::string::npos) {
        withoutLastComponent = "";
        directoryName = dirName;
    } else {
        withoutLastComponent = dirName.substr(0, lastSlash);
        directoryName = dirName.substr(lastSlash + 1);
    }

    uint32_t parentRegion =
        traverseDirectory(diskPath, withoutLastComponent, partitionIndex);

    if (parentRegion == 0) {
        std::cerr << "Error: Parent directory not found." << std::endl;
        return;
    } else {
        int size = 1 + 24 + directoryName.size() + 1 + 4;
        uint64_t freeEntry =
            findFreeDirectoryEntry(diskPath, parentRegion, size);
        if (freeEntry == 0) {
            std::cerr << "Error: No free directory entry found." << std::endl;
            return;
        }
        diskFile.seekp(freeEntry);
        char entryType = 0x2; // Directory entry
        diskFile.write(&entryType, sizeof(entryType));
        uint64_t currentTime = getTime();
        diskFile.write(reinterpret_cast<char *>(&currentTime),
                       sizeof(currentTime));
        diskFile.write(reinterpret_cast<char *>(&currentTime),
                       sizeof(currentTime));
        diskFile.write(reinterpret_cast<char *>(&currentTime),
                       sizeof(currentTime));
        diskFile.write(directoryName.c_str(), directoryName.size());
        diskFile.write("\0", 1);
        uint32_t regionNumber = findFreeRegion(diskPath, partitionIndex);
        if (regionNumber == 0) {
            std::cerr << "Error: No free region found. regionNumber was 0."
                      << std::endl;
            return;
        } else {
            std::cout << "Creating directory in region: " << regionNumber
                      << std::endl;
        }
        diskFile.write(reinterpret_cast<char *>(&regionNumber),
                       sizeof(regionNumber));
        diskFile.seekp(regionNumber * 512);
        char emptyDirEntry[512] = {0};
        emptyDirEntry[0] = DIRECTORY_REGION;
        diskFile.write(emptyDirEntry, sizeof(emptyDirEntry));

        diskFile.seekp(regionNumber * 512 + 1);
        diskFile.write(&entryType, sizeof(entryType));
        diskFile.write(reinterpret_cast<char *>(&currentTime),
                       sizeof(currentTime));
        diskFile.write(reinterpret_cast<char *>(&currentTime),
                       sizeof(currentTime));
        diskFile.write(reinterpret_cast<char *>(&currentTime),
                       sizeof(currentTime));
        std::string currentName = ".";
        diskFile.write(currentName.c_str(), currentName.size());
        diskFile.write("\0", 1); // Null terminator for the name
        diskFile.write(reinterpret_cast<char *>(&regionNumber),
                       sizeof(regionNumber));
        return;
    }
}

uint64_t findFreeDirectoryEntry(const fs::path &diskPath, uint32_t startRegion,
                                int sizeAtLeast) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return 0;
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return 0;
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return 0;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return 0;
    }

    uint32_t currentRegion = startRegion;
    diskFile.seekp(currentRegion * 512); // Go to the start of the directory
    char regionData[512] = {0};
    diskFile.read(regionData, sizeof(regionData));
    int offset = 1;
    while (true) {
        char entryType = regionData[offset];
        offset += 1; // Skip the entry type
        if (entryType == EMPTY_REGION || entryType == DELETED_REGION) {
            if (offset + sizeAtLeast > 508) {
                uint32_t continueRegion =
                    regionData[508] | (regionData[509] << 8) |
                    (regionData[510] << 16) | (regionData[511] << 24);
                if (continueRegion == 0) {
                    std::cout << "No free entry found in the current region."
                              << std::endl;
                    diskFile.seekp(currentRegion * 512 + 508);
                    uint32_t nextRegion = findFreeRegion(diskPath, 0);
                    if (nextRegion == 0) {
                        std::cerr << "Error: No free region found."
                                  << std::endl;
                        return 0;
                    }
                    diskFile.write(reinterpret_cast<char *>(&nextRegion),
                                   sizeof(nextRegion));
                    diskFile.seekp(nextRegion * 512);
                    char emptyDirEntry[512] = {0};
                    emptyDirEntry[0] = DIRECTORY_REGION;
                    diskFile.write(emptyDirEntry, sizeof(emptyDirEntry));
                    return nextRegion * 512 + 1;
                } else {
                    std::cout << "Continuing to next region: " << continueRegion
                              << std::endl;
                    diskFile.seekp(continueRegion * 512);
                    diskFile.read(regionData, sizeof(regionData));
                    currentRegion = continueRegion;
                    offset = 1;
                    continue;
                }
            } else {
                return currentRegion * 512 + (offset - 1);
            }
        }
        offset += 24; // Skip the time
        while (regionData[offset] != '\0') {
            offset++;
        }
        offset++;    // Skip the null terminator of the filename
        offset += 4; // Skip the region number
    }
    return 0;
}

uint32_t findFreeRegion(const fs::path &diskPath, uint32_t partitionNumber,
                        std::vector<uint32_t> ignore) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return 0;
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return 0;
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return 0;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return 0;
    }

    DriveInformation info = getDriveInformation(diskPath).value();
    Partition partition = info.partitions[partitionNumber];
    uint32_t currentRegion = partition.partitionRegion;

    while (currentRegion <
           partition.partitionRegion + partition.partitionSize) {
        char byte;
        diskFile.seekg(currentRegion * 512);
        diskFile.read(&byte, sizeof(byte));
        if (byte == EMPTY_REGION || byte == DELETED_REGION) {
            if (std::find(ignore.begin(), ignore.end(), currentRegion) !=
                ignore.end()) {
                currentRegion++;
                continue;
            }
            return currentRegion;
        } else {
            currentRegion++;
        }
    }
    return 0;
}

uint32_t findFileInDirectory(const fs::path &diskPath,
                             const std::string &fileName, uint32_t region) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return {};
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return {};
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return {};
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return {};
    }

    std::vector<DirectoryEntry> entries =
        parseDirectory(diskPath, region).entries;
    int found = 0;
    while (found < entries.size()) {
        std::string currentPath = entries[found].name;
        if (currentPath == ".") {
            found++;
            continue;
        }
        bool foundEntry = false;
        for (const auto &entry : entries) {
            if (entry.name == currentPath && entry.isDirectory) {
                foundEntry = true;
                entries = parseDirectory(diskPath, entry.region).entries;
                break;
            } else if (entry.name == fileName) {
                foundEntry = true;
                return entry.region;
            }
        }
        if (!foundEntry) {
            std::cerr << "Error: File not found." << std::endl;
            return {};
        }
        found++;
    }

    std::cerr << "Error: File not found." << std::endl;
    return {};
}

void eliminateEntry(std::fstream &diskFile, uint32_t region,
                    const std::string &entryName) {
    diskFile.seekp(region * 512);
    uint32_t nextRegion;
    int offset = 1;
    int entryTypeOffset = 0;
    char regionData[512] = {0};
    diskFile.read(regionData, sizeof(regionData));
    while (true) {
        char entryType = regionData[offset];
        entryTypeOffset = offset;
        offset += 1;
        if (entryType == EMPTY_REGION) {
            nextRegion = regionData[508] | (regionData[509] << 8) |
                         (regionData[510] << 16) | (regionData[511] << 24);
            if (nextRegion == 0) {
                std::cout << "No free entry found in the current region."
                          << std::endl;
                return;
            } else {
                if (nextRegion == 0) {
                    std::cout << "No free entry found in the current region."
                              << std::endl;
                    return;
                }
                diskFile.seekp(nextRegion * 512);
                diskFile.read(regionData, sizeof(regionData));
                offset = 1;
                continue;
            }
            break;
        }
        offset += 24; // Skip the time
        std::string currentName;
        while (regionData[offset] != '\0') {
            currentName += regionData[offset];
            offset++;
        }
        if (currentName == entryName) {
            regionData[entryTypeOffset] = DELETED_REGION;
            diskFile.seekp(region * 512);
            diskFile.write(regionData, sizeof(regionData));
            return;
        }

        offset++;    // Skip the null terminator of the filename
        offset += 4; // Skip the region number
    }
}

void removeRecursive(const fs::path &diskPath, uint32_t directoryRegion) {
    Directory directory = parseDirectory(diskPath, directoryRegion);
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return;
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return;
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return;
    }
    for (const auto &entry : directory.entries) {
        if (entry.isDirectory) {
            removeRecursive(diskPath, entry.region);
        } else {
            eliminateEntry(diskFile, directoryRegion, entry.name);
        }
    }
}

void boot(const fs::path &diskPath, const fs::path &bootPath) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return;
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return;
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return;
    }

    std::ifstream bootFile(bootPath, std::ios::binary);
    if (!bootFile) {
        std::cerr << "Error: Unable to open boot file." << std::endl;
        return;
    }
    std::vector<char> buffer(std::istreambuf_iterator<char>(bootFile), {});
    bootFile.close();
    if (buffer.empty()) {
        std::cerr << "Error: Boot file is empty." << std::endl;
        return;
    }
    if (buffer.size() > 400) {
        std::cerr << "Error: Boot file is too large." << std::endl;
        return;
    }
    diskFile.seekp(0);
    diskFile.write(buffer.data(), buffer.size());
}
