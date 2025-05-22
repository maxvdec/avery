
#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <vector>

namespace fs = std::filesystem;

void formatDisk(const fs::path &diskPath) {
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

    std::uintmax_t diskSize = fs::file_size(diskPath);
    std::cout << "Disk size: " << diskSize << " bytes" << std::endl;

    std::uintmax_t sectorSize = 512;
    std::uintmax_t totalSectors = diskSize / sectorSize;
    std::cout << "Total regions: " << totalSectors << std::endl;

    std::vector<Partition> partitions = {};
    std::vector<std::string> partitionNames = {};

    std::string partition1;
    std::cout << BOLD << GREEN
              << "Enter the name of the first partition: " << RESET;
    std::getline(std::cin, partition1);
    if (trim(partition1).empty()) {
        std::cerr << "Error: Partition name cannot be empty." << std::endl;
        return;
    }

    if (partition1.length() > 17) {
        std::cerr << "Error: Partition name is too long." << std::endl;
        return;
    } else if (partition1.length() < 17) {
        int remainingSpaces = 17 - partition1.length();
        partition1.append(remainingSpaces, ' ');
    }
    partition1[17] = '\0';
    partitionNames.push_back(partition1);

    int usedPartitions = 1;
    for (int i = 1; i < 4; i++) {
        std::string partitionName;
        std::cout << BOLD << GREEN << "Enter the name of partition " << i + 1
                  << " (empty will be unused): " << RESET;
        std::getline(std::cin, partitionName);
        if (trim(partitionName).empty()) {
            continue;
        }

        if (partitionName.length() > 17) {
            std::cerr << "Error: Partition name is too long." << std::endl;
            return;
        } else if (partitionName.length() < 17) {
            int remainingSpaces = 17 - partitionName.length();
            partitionName.append(remainingSpaces, ' ');
        }
        partitionName[17] = '\0';
        partitionNames.push_back(partitionName);
        usedPartitions++;
    }

    const std::uint32_t partitionSize = (totalSectors - 1) / usedPartitions;
    std::cout << "Each partition will be assigned " << partitionSize
              << " sectors." << std::endl;
    bool confirm = readYesOrNo(
        "Are you sure you want to format the disk with these partitions?");
    int currentRegion = 0x1;
    if (!confirm) {
        for (int i = 0; i < usedPartitions; i++) {
            std::cout << "Indicate the partition " << trim(partitionNames[i])
                      << " size in sectors, or in "
                         "percentages ending with % (e.g. 50%): ";
            std::string partitionSizeInput;
            std::getline(std::cin, partitionSizeInput);
            std::uint32_t currentPartitionSize = 0;
            if (partitionSizeInput.back() == '%') {
                partitionSizeInput.pop_back();
                int percentage = std::stoi(partitionSizeInput);
                if (percentage < 0 || percentage > 100) {
                    std::cerr << "Error: Invalid percentage." << std::endl;
                    return;
                }
                currentPartitionSize = ((totalSectors - 1) * percentage) / 100;
            } else {
                currentPartitionSize = std::stoi(partitionSizeInput);
            }
            std::uint32_t start = currentRegion;
            currentRegion += currentPartitionSize;
            if (currentRegion > totalSectors) {
                std::cerr << "Error: Partition size exceeds disk size."
                          << std::endl;
                return;
            }
            std::cout << "Partition " << trim(partitionNames[i]) << " gets "
                      << currentPartitionSize << " sectors." << std::endl;

            Partition p;
            p.usable = true;
            p.partitionRegion = start;
            p.partitionSize = currentPartitionSize;
            std::strncpy(p.name, partitionNames[i].c_str(), 18);
            partitions.push_back(p);
        }
    } else {
        for (int i = 0; i < usedPartitions; i++) {
            std::uint32_t start = currentRegion;
            currentRegion += partitionSize;
            if (currentRegion > totalSectors) {
                std::cerr << "Error: Partition size exceeds disk size."
                          << std::endl;
                return;
            }
            Partition p;
            p.usable = true;
            p.partitionRegion = start;
            p.partitionSize = partitionSize;
            std::strncpy(p.name, partitionNames[i].c_str(), 18);
            partitions.push_back(p);
        }
    }

    for (int i = 0; i < 4 - usedPartitions; i++) {
        Partition p;
        p.usable = false;
        p.partitionRegion = 0;
        p.partitionSize = 0;
        std::strncpy(p.name, "unused", 18);
        partitions.push_back(p);
    }

    char bootCode[400] = {0};
    diskFile.write(bootCode, sizeof(bootCode));
    for (const Partition &partition : partitions) {
        if (partition.usable) {
            diskFile.write(partition.name, 18);
            diskFile.write(
                reinterpret_cast<const char *>(&partition.partitionRegion), 4);
            diskFile.write(
                reinterpret_cast<const char *>(&partition.partitionSize), 4);
        } else {
            char empty[26] = {0}; // 18 + 4 + 4 = 26
            diskFile.write(empty, sizeof(empty));
        }
    }
    diskFile.write("IONFS", 5);
    diskFile.write(reinterpret_cast<const char *>(&IONICFS_VERSION),
                   sizeof(IONICFS_VERSION));
    for (const Partition &partition : partitions) {
        if (!partition.usable) {
            continue;
        }
        const int partitionRoot = partition.partitionRegion;
        diskFile.seekp(partitionRoot * sectorSize);
        char directoryRegion = DIRECTORY_REGION;
        diskFile.write(&directoryRegion, 1);
        std::uintmax_t offset = 1;
        char emptyRegion[512] = {EMPTY_REGION};
        diskFile.write(&directoryRegion, 1);

        char time[8] = {0};
        std::uint64_t currentTime = getTime();
        std::memcpy(time, &currentTime, sizeof(currentTime));
        diskFile.write(time, sizeof(time));
        diskFile.write(time, sizeof(time));
        diskFile.write(time, sizeof(time));
        diskFile.write(".\0", 2);

        char partitionEntry[4] = {0};
        partitionEntry[0] = partition.partitionRegion;
        partitionEntry[1] = partition.partitionRegion >> 8;
        partitionEntry[2] = partition.partitionRegion >> 16;
        partitionEntry[3] = partition.partitionRegion >> 24;
        diskFile.write(partitionEntry, 4);

        while (offset < partition.partitionSize * sectorSize) {
            diskFile.write(emptyRegion, 1);
            int percentage =
                (100 * offset) / (partition.partitionSize * sectorSize);
            if (percentage % 25 == 0) {
                std::cout << "\r" << BOLD << GREEN << "Formatting partition "
                          << trim(partition.name) << ": " << percentage
                          << "% done." << RESET << std::flush;
            }
            offset++;
        }
        std::cout << "\r" << BOLD << GREEN << "Formatting partition "
                  << trim(partition.name) << ": " << "100"
                  << "% done." << RESET << std::endl;
        std::cout << "Partition " << trim(partition.name)
                  << " formatted successfully." << std::endl;
    }
}