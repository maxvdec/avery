#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <vector>

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

    std::vector<DirectoryEntry> entries =
        parseRootDirectory(diskPath, partitionIndex).entries;
    std::vector<std::string> pathItems = {};
    std::string path = directoryName;
    std::string delimiter = "/";
    size_t pos = 0;
    while ((pos = path.find(delimiter)) != std::string::npos) {
        std::string token = path.substr(0, pos);
        pathItems.push_back(token);
        path.erase(0, pos + delimiter.length());
    }
    pathItems.push_back(path);
    int found = 0;
    while (found < pathItems.size()) {
        std::string currentPath = pathItems[found];
        bool foundEntry = false;
        for (const auto &entry : entries) {
            if (entry.name == currentPath && entry.isDirectory) {
                foundEntry = true;
                entries = parseDirectory(diskPath, entry.region).entries;
                break;
            }
        }
        if (!foundEntry) {
            std::cerr << "Error: Directory not found." << std::endl;
            return {};
        }
        found++;
    }

    if (found == pathItems.size()) {
        for (const auto &entry : entries) {
            if (entry.name == pathItems[found - 1]) {
                return entry.region;
            }
        }
    }
    std::cerr << "Error: Directory not found." << std::endl;
    return {};
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

    std::string withoutLastComponent =
        dirName.substr(0, dirName.find_last_of('/'));
    uint32_t parentRegion =
        traverseDirectory(diskPath, withoutLastComponent, partitionIndex);

    std::string directoryName = dirName.substr(dirName.find_last_of('/') + 1);

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
        diskFile.write(directoryName.c_str(), dirName.size());
        diskFile.write("\0", 1); // Null terminator for the name
        uint32_t regionNumber = findFreeRegion(diskPath, partitionIndex);
        if (regionNumber == 0) {
            std::cerr << "Error: No free region found. regionNumber was 0."
                      << std::endl;
            return;
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
        if (entryType == 0x0) {
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

uint32_t findFreeRegion(const fs::path &diskPath, uint32_t partitionNumber) {
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
            std::cout << "Found free region: " << currentRegion << std::endl;
            return currentRegion;
        } else {
            currentRegion++;
        }
    }
    return 0;
}