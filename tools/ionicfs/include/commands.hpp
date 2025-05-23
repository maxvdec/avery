#ifndef COMMANDS_HPP
#define COMMANDS_HPP

#include <filesystem>
#include <optional>
#include <string>

namespace fs = std::filesystem;

#define IONICFS_VERSION "001"

#define BOLD "\033[1m"
#define GREEN "\033[32m"
#define RED "\033[31m"
#define YELLOW "\033[33m"
#define RESET "\033[0m"
#define CYAN "\033[36m"

#define EMPTY_REGION 0x0
#define DELETED_REGION 0x1
#define DIRECTORY_REGION 0x2
#define FILE_REGION 0x3

struct Partition {
    char name[18];
    std::uint32_t partitionRegion;
    std::uint32_t partitionSize; // in regions
    bool usable = true;
} __attribute__((packed));

struct DriveInformation {
    Partition partitions[4];
    char bootCode[400];
    std::uintmax_t diskSize;
    std::uintmax_t totalRegions;
    char version[9];
};

struct DirectoryEntry {
    std::string name;
    uint64_t lastAccessed;
    uint64_t lastModified;
    uint64_t created;
    uint32_t region;
    bool isDirectory;
};

struct Directory {
    uint32_t region;
    std::vector<DirectoryEntry> entries;
};

void formatDisk(const fs::path &diskPath);
std::optional<DriveInformation> getDriveInformation(const fs::path &diskPath);
void info(const fs::path &diskPath);
Directory parseRootDirectory(const fs::path &diskPath, int partitionIndex);
Directory parseDirectory(const fs::path &diskPath, uint32_t region);
uint32_t traverseDirectory(const fs::path &diskPath,
                           const std::string &directoryName,
                           int partitionIndex);
void createDirectory(const fs::path &diskPath, const std::string &dirName,
                     int partitionIndex);
void copyFile(const fs::path &diskPath, const std::string &fileName,
              const std::string path, int partitionIndex);
uint64_t findFreeDirectoryEntry(const fs::path &diskPath, uint32_t startRegion,
                                int sizeAtLeast);
uint32_t findFreeRegion(const fs::path &diskPath, uint32_t partitionNumber,
                        std::vector<uint32_t> ignore = {});
void readFile(const fs::path &diskPath, const std::string &fileName,
              int partitionIndex, bool hex = false);
uint32_t findFileInDirectory(const fs::path &diskPath,
                             const std::string &fileName, uint32_t region);
void removeFile(const fs::path &diskPath, const std::string &fileName,
                int partitionIndex);
void removeDirectory(const fs::path &diskPath, const std::string &dirName,
                     int partitionIndex);
void eliminateEntry(std::fstream &diskFile, uint32_t region,
                    const std::string &entryName);
void removeRecursive(const fs::path &diskPath, uint32_t directoryRegion);
void boot(const fs::path &diskPath, const fs::path &bootPath);

#endif // COMMANDS_HPP