
#include "commands.hpp"
#include "utils.hpp"
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

int main(int argc, char *argv[]) {
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
    } else {
        std::cerr << "Unknown command: " << argv[1] << std::endl;
        std::cerr << "Usage: " << argv[0] << " <disk_path>" << std::endl;
        return 1;
    }
    return 0;
}