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
        diskFile.seekg(currentRegion * 512);
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

    if (parentRegion == 0) {
        std::cerr << "Error: Parent directory not found." << std::endl;
        return;
    } else {
        std::cout << "Parent directory found at region: " << std::hex
                  << parentRegion << std::endl;
        return;
    }
}