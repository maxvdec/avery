
#include <chrono>
#include <iostream>
#include <string>
#include <utils.hpp>

std::string trim(const std::string &str) {
    size_t first = str.find_first_not_of(' ');
    if (first == std::string::npos) {
        return "";
    }
    size_t last = str.find_last_not_of(' ');
    return str.substr(first, last - first + 1);
}

bool readYesOrNo(const std::string &prompt) {
    std::string input;
    while (true) {
        std::cout << BOLD << GREEN << prompt << " (y/n): " << RESET;
        std::getline(std::cin, input);
        if (input == "y" || input == "Y") {
            return true;
        } else if (input == "n" || input == "N") {
            return false;
        } else {
            std::cout << "Invalid input. Please enter 'y' or 'n'." << std::endl;
        }
    }
}

std::string unixTimeToString(uint64_t unixTime) {
    std::chrono::time_point<std::chrono::system_clock> timePoint =
        std::chrono::system_clock::from_time_t(unixTime);
    std::time_t time = std::chrono::system_clock::to_time_t(timePoint);
    char buffer[26];
    ctime_r(&time, buffer);
    buffer[24] = '\0'; // Remove the newline character
    return std::string(buffer);
}

uint64_t getTime() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}