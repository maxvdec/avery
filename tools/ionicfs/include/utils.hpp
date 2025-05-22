
#ifndef UTILS_H
#define UTILS_H

#include <string>

#define BOLD "\033[1m"
#define GREEN "\033[32m"
#define RED "\033[31m"
#define YELLOW "\033[33m"
#define RESET "\033[0m"
#define CYAN "\033[36m"

std::string trim(const std::string &str);
bool readYesOrNo(const std::string &prompt);
std::string unixTimeToString(uint64_t unixTime);
uint64_t getTime();

#endif // UTILS_H