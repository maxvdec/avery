#include "commands.hpp"
#include "utils.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <vector>

namespace fs = std::filesystem;

void readFile(const fs::path &diskPath, const std::string &fileName,
              int partitionIndex, bool hex) {
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

    std::string filePath = fileName;
    std::string dirPath;
    std::string bareFileName;

    size_t lastSlashPos = filePath.find_last_of('/');
    if (lastSlashPos != std::string::npos) {
        dirPath = filePath.substr(0, lastSlashPos);
        bareFileName = filePath.substr(lastSlashPos + 1);
    } else {
        dirPath = "."; // Current directory
        bareFileName = filePath;
    }

    uint32_t directoryRegion =
        traverseDirectory(diskPath, dirPath, partitionIndex);

    uint32_t region =
        findFileInDirectory(diskPath, bareFileName, directoryRegion);
    if (region == 0) {
        std::cerr << "Error: File not found." << std::endl;
        return;
    }
    diskFile.seekg(region * 512);
    std::vector<char> buffer;
    while (true) {
        char byte;
        diskFile.read(&byte, sizeof(byte));
        if (byte == FILE_REGION) {
            char fileData[507];
            diskFile.read(fileData, sizeof(fileData));
            buffer.insert(buffer.end(), fileData, fileData + sizeof(fileData));
            uint32_t nextRegion;
            diskFile.read(reinterpret_cast<char *>(&nextRegion),
                          sizeof(nextRegion));
            if (nextRegion == 0) {
                break;
            }
            region = nextRegion;
            diskFile.seekg(region * 512);
        } else {
            break;
        }
    }

    if (buffer.empty()) {
        std::cerr << "Error: File is empty." << std::endl;
        return;
    }
    if (hex) {
        for (const auto &byte : buffer) {
            std::cout << std::hex << static_cast<int>(byte) << " ";
        }
        std::cout << std::dec << std::endl;
    } else {
        std::cout.write(buffer.data(), buffer.size());
        std::cout << std::endl;
    }
    diskFile.close();
    std::cout << "File read successfully." << std::endl;
    std::cout << "File size: " << buffer.size() << " bytes." << std::endl;
    std::cout << "File region: " << std::hex << region << std::dec << std::endl;
}