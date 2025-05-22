
#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

namespace fs = std::filesystem;

std::optional<DriveInformation> getDriveInformation(const fs::path &diskPath) {
    if (!fs::exists(diskPath)) {
        std::cerr << "Error: Disk path does not exist." << std::endl;
        return std::nullopt;
    }

    if (fs::is_directory(diskPath)) {
        std::cerr << "Error: Disk path is a directory." << std::endl;
        return std::nullopt;
    }

    if (fs::is_empty(diskPath)) {
        std::cerr << "Error: Disk path is empty." << std::endl;
        return std::nullopt;
    }

    std::fstream diskFile(diskPath,
                          std::ios::in | std::ios::out | std::ios::binary);
    if (!diskFile) {
        std::cerr << "Error: Unable to open disk file." << std::endl;
        return std::nullopt;
    }

    const std::uintmax_t diskSize = fs::file_size(diskPath);
    const std::uintmax_t sectorSize = 512;
    const std::uintmax_t totalSectors = diskSize / sectorSize;

    DriveInformation driveInfo;
    diskFile.read(reinterpret_cast<char *>(&driveInfo.bootCode),
                  sizeof(driveInfo.bootCode));
    for (int i = 0; i < 4; ++i) {
        Partition p;
        diskFile.read(reinterpret_cast<char *>(&p.name), sizeof(p.name));
        diskFile.read(reinterpret_cast<char *>(&p.partitionRegion),
                      sizeof(p.partitionRegion));
        diskFile.read(reinterpret_cast<char *>(&p.partitionSize),
                      sizeof(p.partitionSize));
        if (p.partitionSize > 0) {
            p.usable = true;
        } else {
            p.usable = false;
        }
        driveInfo.partitions[i] = p;
    }

    diskFile.read(reinterpret_cast<char *>(&driveInfo.version), 8);
    driveInfo.version[8] = '\0'; // Ensure null-termination
    driveInfo.diskSize = diskSize;
    driveInfo.totalRegions = totalSectors;
    return driveInfo;
}

void info(const fs::path &diskPath) {
    auto driveInfo = getDriveInformation(diskPath);
    if (!driveInfo) {
        std::cerr << "Error: Unable to retrieve drive information."
                  << std::endl;
        return;
    }

    std::cout << BOLD << GREEN << "Drive Information:" << RESET << std::endl;
    std::cout << "Disk Size: " << driveInfo->diskSize << " bytes" << std::endl;
    std::cout << "Total Regions: " << driveInfo->totalRegions << std::endl;
    std::cout << "Using IonicFS Version: " << driveInfo->version << std::endl;

    for (const auto &partition : driveInfo->partitions) {
        if (partition.usable) {
            std::cout << "Partition Name: " << trim(partition.name)
                      << ", Region: " << partition.partitionRegion
                      << ", Size: " << partition.partitionSize << " sectors"
                      << std::endl;
        }
    }
}