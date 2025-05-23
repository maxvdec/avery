#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <vector>

namespace fs = std::filesystem;

void removeFile(const fs::path &diskPath, const std::string &fileName,
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
        fileName.substr(0, fileName.find_last_of("/\\"));
    std::string lastComponent =
        fileName.substr(fileName.find_last_of("/\\") + 1);
    uint32_t parentRegion =
        traverseDirectory(diskPath, withoutLastComponent, partitionIndex);
    if (parentRegion == 0) {
        std::cerr << "Error: Unable to find parent directory." << std::endl;
        return;
    }
    eliminateEntry(diskFile, parentRegion, lastComponent);
    uint32_t fileRegion =
        findFileInDirectory(diskPath, lastComponent, parentRegion);
    std::cout << "File region: " << fileRegion << std::endl;
    if (fileRegion == 0) {
        std::cerr << "Error: File not found." << std::endl;
        return;
    }
    while (true) {
        diskFile.seekp(fileRegion * 512);
        char entryType = DELETED_REGION;
        diskFile.write(&entryType, sizeof(entryType));
        char region[512];
        diskFile.seekp(fileRegion * 512);
        diskFile.read(region, sizeof(region));
        uint32_t nextRegion = region[508] | (region[509] << 8) |
                              (region[510] << 16) | (region[511] << 24);
        if (nextRegion == 0) {
            break;
        }
        fileRegion = nextRegion;
    }
}

void removeDirectory(const fs::path &diskPath, const std::string &fileName,
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
        fileName.substr(0, fileName.find_last_of("/\\"));
    std::string lastComponent =
        fileName.substr(fileName.find_last_of("/\\") + 1);
    uint32_t parentRegion =
        traverseDirectory(diskPath, withoutLastComponent, partitionIndex);
    uint32_t directoryRegion =
        traverseDirectory(diskPath, fileName, parentRegion);
    if (directoryRegion == 0) {
        std::cerr << "Error: Unable to find directory." << std::endl;
        return;
    }
    removeRecursive(diskPath, directoryRegion);
    if (parentRegion == 0) {
        std::cerr << "Error: Unable to find parent directory." << std::endl;
        return;
    }
    eliminateEntry(diskFile, parentRegion, lastComponent);
    while (true) {
        char entryType = DELETED_REGION;
        diskFile.write(&entryType, sizeof(entryType));
        char region[512];
        diskFile.read(region, sizeof(region));
        uint32_t nextRegion = region[508] | (region[509] << 8) |
                              (region[510] << 16) | (region[511] << 24);
        if (nextRegion == 0) {
            break;
        }
    }
}