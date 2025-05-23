
#include "commands.hpp"
#include "utils.hpp"
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

std::string getVersion() {
    std::string versionStr = IONICFS_VERSION;
    std::string formattedVersion = versionStr.substr(0, 1) + "." +
                                   versionStr.substr(1, 1) + "." +
                                   versionStr.substr(2, 1);
    return formattedVersion;
}

int main(int argc, char *argv[]) {
    if (argv[1] == nullptr) {
        std::cout << "IonicFS Tooling" << std::endl;
        std::cout << "Created by Max Van den Eynde for the Avery project."
                  << std::endl;
        std::cout << "Version: " << getVersion() << std::endl;
        std::cout << "Copyright (c) 2025 Max Van den Eynde" << std::endl;
        return 0;
    }
    if (strcmp(argv[1], "help") == 0) {
        std::cout << "Usage: " << argv[0] << " <command> [options]"
                  << std::endl;
        std::cout << "Commands:" << std::endl;
        std::cout << "  format <disk_path>" << std::endl;
        std::cout << "  info <disk_path>" << std::endl;
        std::cout << "  list <disk_path> [partition_index]" << std::endl;
        std::cout << "  mkdir <disk_path> <dir_name> [partition_index]"
                  << std::endl;
        std::cout << "  copy <disk_path> <file_name> <dest_path> "
                     "[partition_index]"
                  << std::endl;
        std::cout << "  read <disk_path> <file_name> [partition_index]"
                  << std::endl;
        std::cout << "  read -hex <disk_path> <file_name> "
                     "[partition_index]"
                  << std::endl;
        std::cout << "  rm <disk_path> <file_name> [partition_index]"
                  << std::endl;
        std::cout << "  rm-dir <disk_path> <dir_name> [partition_index]"
                  << std::endl;
        std::cout << "  boot <disk_path> <boot_file_path>" << std::endl;
        std::cout << "  version" << std::endl;
        std::cout << "  help" << std::endl;
        return 0;
    } else if (strcmp(argv[1], "version") == 0) {
        std::cout << "IonicFS Tooling" << std::endl;
        std::cout << "Created by Max Van den Eynde for the Avery project."
                  << std::endl;
        std::cout << "Version: " << getVersion() << std::endl;
        std::cout << "Copyright (c) 2025 Max Van den Eynde" << std::endl;
        return 0;
    }
    if (argc <= 2) {
        std::cerr << "Usage: " << argv[0] << " <disk_path>" << std::endl;
        return 1;
    }

    if (strcmp(argv[1], "format") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        formatDisk(diskPath);
    } else if (strcmp(argv[1], "info") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        info(diskPath);
    } else if (strcmp(argv[1], "list") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        int partitionIndex = 0;
        if (argc > 3) {
            partitionIndex = std::stoi(argv[3]);
        }
        auto entries = parseRootDirectory(diskPath, partitionIndex).entries;
        if (entries.empty()) {
            std::cout << "No entries found in the directory." << std::endl;
            return 1;
        }
        std::cout << BOLD << "Files at ROOT MODULE. Partition "
                  << partitionIndex << ":" << RESET << std::endl;
        for (const auto &entry : entries) {
            std::cout << entry.name;
            if (entry.isDirectory) {
                std::cout << "/";
            }
            std::cout << " (Last Accessed: "
                      << unixTimeToString(entry.lastAccessed)
                      << ", Last Modified: "
                      << unixTimeToString(entry.lastModified)
                      << ", Created: " << unixTimeToString(entry.created)
                      << ", Region: " << std::hex << entry.region
                      << ", Is Directory: "
                      << (entry.isDirectory ? "Yes" : "No") << ")" << std::endl;
        }
    } else if (strcmp(argv[1], "mkdir") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        std::string dirName(argv[3]);
        int partitionIndex = 0;
        if (argc > 4) {
            partitionIndex = std::stoi(argv[4]);
        }
        createDirectory(diskPath, dirName, partitionIndex);
    } else if (strcmp(argv[1], "copy") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        std::string fileName(argv[3]);
        std::string destPath(argv[4]);
        int partitionIndex = 0;
        if (argc > 5) {
            partitionIndex = std::stoi(argv[5]);
        }
        copyFile(diskPath, fileName, destPath, partitionIndex);
    } else if (strcmp(argv[1], "read") == 0) {
        if (strcmp(argv[2], "-hex") == 0) {
            std::string path(argv[3]);
            fs::path diskPath(path);
            std::string fileName(argv[4]);
            int partitionIndex = 0;
            if (argc > 5) {
                partitionIndex = std::stoi(argv[5]);
            }
            readFile(diskPath, fileName, partitionIndex, true);
        } else {
            std::string path(argv[2]);
            fs::path diskPath(path);
            std::string fileName(argv[3]);
            int partitionIndex = 0;
            if (argc > 4) {
                partitionIndex = std::stoi(argv[4]);
            }
            readFile(diskPath, fileName, partitionIndex, false);
        }
    } else if (strcmp(argv[1], "rm") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        std::string fileName(argv[3]);
        int partitionIndex = 0;
        if (argc > 4) {
            partitionIndex = std::stoi(argv[4]);
        }
        removeFile(diskPath, fileName, partitionIndex);
    } else if (strcmp(argv[1], "rm-dir") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        std::string dirName(argv[3]);
        int partitionIndex = 0;
        if (argc > 4) {
            partitionIndex = std::stoi(argv[4]);
        }
        removeDirectory(diskPath, dirName, partitionIndex);
    } else if (strcmp(argv[1], "boot") == 0) {
        std::string path(argv[2]);
        fs::path diskPath(path);
        std::string bootPath(argv[3]);
        boot(diskPath, bootPath);
    } else {
        std::cerr << "Unknown command: " << argv[1] << std::endl;
        std::cerr << "Usage: " << argv[0] << " <disk_path>" << std::endl;
        return 1;
    }
    return 0;
}