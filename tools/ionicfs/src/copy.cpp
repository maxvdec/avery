#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

void copyFile(const fs::path &diskPath, const std::string &fileName,
              const std::string path, int partitionIndex) {
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

    // Fix: Properly resolve the source file path
    fs::path sourceFilePath;
    try {
        sourceFilePath = fs::canonical(fs::path(fileName));
        std::cout << "Resolved source file path: " << sourceFilePath
                  << std::endl;
    } catch (const fs::filesystem_error &e) {
        // If canonical fails (file doesn't exist), try absolute
        try {
            sourceFilePath = fs::absolute(fs::path(fileName));
            std::cout << "Resolved source file path (absolute): "
                      << sourceFilePath << std::endl;
        } catch (const fs::filesystem_error &e2) {
            std::cerr << "Error: Unable to resolve file path: " << fileName
                      << " - " << e2.what() << std::endl;
            return;
        }
    }

    std::ifstream sourceFile(sourceFilePath, std::ios::binary);
    if (!sourceFile) {
        std::cerr << "Error: Unable to open source file at " << sourceFilePath
                  << std::endl;
        return;
    }
    std::vector<char> buffer(std::istreambuf_iterator<char>(sourceFile), {});
    sourceFile.close();
    if (buffer.empty()) {
        std::cerr << "Error: Source file is empty." << std::endl;
        return;
    }

    // Fix: Properly extract directory and filename components using filesystem
    fs::path destinationPath(path);
    std::string parentDirectory = destinationPath.parent_path().string();
    std::string lastComponent = destinationPath.filename().string();

    // Convert to forward slashes for consistency (if needed by your filesystem)
    std::replace(parentDirectory.begin(), parentDirectory.end(), '\\', '/');

    std::cout << "Parent directory: '" << parentDirectory << "'" << std::endl;
    std::cout << "File name: '" << lastComponent << "'" << std::endl;

    uint32_t parentRegion =
        traverseDirectory(diskPath, parentDirectory, partitionIndex);
    if (parentRegion == 0) {
        std::cerr << "Error: Unable to find parent directory: "
                  << parentDirectory << std::endl;
        return;
    }

    int size = 1 + 24 + lastComponent.size() + 1 + 4;
    uint64_t freeEntry = findFreeDirectoryEntry(diskPath, parentRegion, size);
    if (freeEntry == 0) {
        std::cerr << "Error: No free directory entry found." << std::endl;
        return;
    }

    uint32_t neededRegions = buffer.size() / 507;
    if (buffer.size() % 507 != 0) {
        neededRegions++;
    }
    std::cout << "Needed regions: " << neededRegions << std::endl;

    std::vector<uint32_t> freeRegions;
    for (int i = 0; i < neededRegions; i++) {
        uint32_t freeRegion =
            findFreeRegion(diskPath, partitionIndex, freeRegions);
        if (freeRegion == 0) {
            std::cerr << "Error: No free region found." << std::endl;
            return;
        }
        freeRegions.push_back(freeRegion);
    }
    std::cout << "Free regions: ";
    for (const auto &region : freeRegions) {
        std::cout << region << " ";
    }
    std::cout << std::endl;

    for (int i = 0; i < neededRegions; i++) {
        diskFile.seekp(freeRegions[i] * 512);

        char regionData[512] = {0};

        regionData[0] = FILE_REGION;

        size_t dataStart = i * 507;
        size_t dataSize =
            std::min(static_cast<size_t>(507), buffer.size() - dataStart);

        std::memcpy(regionData + 1, buffer.data() + dataStart, dataSize);

        uint32_t nextRegion = 0;
        if (i < neededRegions - 1) {
            nextRegion = freeRegions[i + 1];
        }
        std::memcpy(regionData + 508, &nextRegion, sizeof(nextRegion));

        diskFile.write(regionData, 512);
    }

    diskFile.seekp(freeEntry);
    char entryType = 0x3; // File entry
    diskFile.write(&entryType, sizeof(entryType));
    uint64_t currentTime = getTime();
    diskFile.write(reinterpret_cast<char *>(&currentTime), sizeof(currentTime));
    diskFile.write(reinterpret_cast<char *>(&currentTime), sizeof(currentTime));
    diskFile.write(reinterpret_cast<char *>(&currentTime), sizeof(currentTime));
    diskFile.write(lastComponent.c_str(), lastComponent.size());
    diskFile.write("\0", 1); // Null terminator for the name
    uint32_t regionNumber = freeRegions[0];
    diskFile.write(reinterpret_cast<char *>(&regionNumber),
                   sizeof(regionNumber));
}