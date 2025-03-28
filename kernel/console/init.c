/*
 init.c
 As part of the Avery project
 Created by Maxims Enterprise in 2025
 --------------------------------------------------
 Description: Console entry point and basic commands
 Copyright (c) 2025 Maxims Enterprise
*/

#include "common.h"
#include "console.h"
#include "disk/fat32.h"
#include "vga.h"

str current_dir = "/";

#define MAX_PATH_LENGTH 256

void init_console() {
    while (true) {
        write(current_dir);
        str input = read_line(" > ");
        if (strncmp(input, "ls", 2) == 0) {
            toupper(current_dir);
            list_dir(current_dir);
            tolower(current_dir);
        } else if (strncmp(input, "cd", 2) == 0) {
            str path = input + 3;
            str backup = current_dir;

            if (strncmp(path, "..", 2) == 0) {
                if (strlen(current_dir) > 1) {
                    for (int i = strlen(current_dir) - 2; i >= 0; i--) {
                        if (current_dir[i] != '/' && current_dir[i] != 0) {
                            current_dir[i] = 0;
                        } else {
                            break;
                        }
                    }
                }

                size len = strlen(current_dir);
                if (current_dir[len - 1] == '/' && len > 1) {
                    current_dir[len - 1] = 0;
                }
                continue;
            } else if (strncmp(path, ".", 1) == 0) {
                continue;
            }

            if (path[0] == '.' && path[1] == '/') {
                current_dir = concat(current_dir, path + 2);
            } else if (strncmp(path, "/", 1) == 0) {
                current_dir = "/";
                continue;
            } else if (path[0] == '/') {
                strncpy(current_dir, path, MAX_PATH_LENGTH);
            } else if (strncmp(current_dir, "/", 1) == 0) {
                current_dir = concat(concat(current_dir, ""), path);
            } else {
                current_dir = concat(concat(current_dir, "/"), path);
            }

            if (!dir_exists(current_dir)) {
                toupper(current_dir);
                if (!dir_exists(current_dir)) {
                    write("ERROR: Directory not found\n");
                    strncpy(current_dir, backup, MAX_PATH_LENGTH);
                }
                tolower(current_dir);
            }
        } else if (strncmp(input, "clear", 5) == 0) {
            clear();
        } else if (strncmp(input, "about", 5) == 0) {
            write("Avery Kernel\n");
            write("Development Version\n");
            write("Build ");
            write(BUILD);
            write("\n");
            write("Type 'help' for a list of commands\n Type 'settings' to "
                  "enter system settings\n");
            write("All systems are operational\n");
        } else if (strncmp(input, "new -d", 6) == 0) {
            str dir = input + 7;
            if (dir[0] == '.' && dir[1] == '/') {
                dir = concat(current_dir, dir + 2);
            } else if (strncmp(dir, "/", 1) == 0) {
                dir = "/";
            } else if (dir[0] == '/') {
                strncpy(dir, dir, MAX_PATH_LENGTH);
            } else if (strncmp(current_dir, "/", 1) == 0) {
                dir = concat(concat(current_dir, ""), dir);
            } else {
                dir = concat(concat(current_dir, "/"), dir);
            }

            toupper(dir);

            if (dir_exists(dir)) {
                write("ERROR: Directory already exists\n");
            } else {
                create_dir(dir);
            }
        } else if (strncmp(input, "new", 3) == 0) {
            str file = input + 4;
            if (file[0] == '.' && file[1] == '/') {
                file = concat(current_dir, file + 2);
            } else if (strncmp(file, "/", 1) == 0) {
                file = "/";
            } else if (file[0] == '/') {
                strncpy(file, file, MAX_PATH_LENGTH);
            } else if (strncmp(current_dir, "/", 1) == 0) {
                file = concat(concat(current_dir, ""), file);
            } else {
                file = concat(concat(current_dir, "/"), file);
            }

            toupper(file);

            if (file_exists(file)) {
                write("ERROR: File already exists\n");
            } else {
                create_file(file);
            }
        } else if (strncmp(input, "exists? -d", 10) == 0) {
            str dir = input + 11;
            if (dir[0] == '.' && dir[1] == '/') {
                dir = concat(current_dir, dir + 2);
            } else if (strncmp(dir, "/", 1) == 0) {
                dir = "/";
                continue;
            } else if (dir[0] == '/') {
                strncpy(dir, dir, MAX_PATH_LENGTH);
            } else if (strncmp(current_dir, "/", 1) == 0) {
                dir = concat(concat(current_dir, ""), dir);
            } else {
                dir = concat(concat(current_dir, "/"), dir);
            }

            if (!dir_exists(dir)) {
                toupper(dir);
                if (!dir_exists(dir)) {
                    write("-> false\n");
                    continue;
                }
            }
            write("-> true\n");

        } else if (strncmp(input, "exists?", 7) == 0) {
            str file = input + 8;
            if (file[0] == '.' && file[1] == '/') {
                file = concat(current_dir, file + 2);
            } else if (strncmp(file, "/", 1) == 0) {
                file = "/";
            } else if (file[0] == '/') {
                strncpy(file, file, MAX_PATH_LENGTH);
            } else if (strncmp(current_dir, "/", 1) == 0) {
                file = concat(concat(current_dir, ""), file);
            } else {
                file = concat(concat(current_dir, "/"), file);
            }

            toupper(file);

            u32 cluster = fat32_find_cluster(file);
            if (cluster == 0xFFFFFFFF) {
                write("-> false\n");
            } else {
                write("-> true\n");
            }
        } else if (strncmp(input, "read -hex", 9) == 0) {
            str file = input + 10;
            if (file[0] == '.' && file[1] == '/') {
                file = concat(current_dir, file + 2);
            } else if (strncmp(file, "/", 1) == 0 && strlen(file) == 1) {
                file = "/";
            } else if (file[0] == '/') {
            } else if (strncmp(current_dir, "/", 1) == 0 &&
                       strlen(current_dir) == 1) {
                file = concat(concat(current_dir, ""), file);
            } else {
                file = concat(concat(current_dir, "/"), file);
            }

            toupper(file);

            str content = read_file(file);
            if (content == NULL) {
                write("ERROR: File not found\n");
            } else {
                for (size i = 0; content[i] != '\0'; i++) {
                    write_hex(content[i]);
                    write(" ");
                }
                write("\n");
            }
        } else if (strncmp(input, "exec", 4) == 0) {
            str file = input + 5;
            if (file[0] == '.' && file[1] == '/') {
                file = concat(current_dir, file + 2);
            } else if (strncmp(file, "/", 1) == 0 && strlen(file) == 1) {
                file = "/";
            } else if (file[0] == '/') {
            } else if (strncmp(current_dir, "/", 1) == 0 &&
                       strlen(current_dir) == 1) {
                file = concat(concat(current_dir, ""), file);
            } else {
                file = concat(concat(current_dir, "/"), file);
            }

            toupper(file);

            str content = read_file(file);
            if (content == NULL) {
                write("ERROR: File not found\n");
            } else {
                execute((u8 *)content);
            }
        } else if (strncmp(input, "read", 4) == 0) {
            str file = input + 5;
            if (file[0] == '.' && file[1] == '/') {
                file = concat(current_dir, file + 2);
            } else if (strncmp(file, "/", 1) == 0 && strlen(file) == 1) {
                file = "/";
            } else if (file[0] == '/') {
                strncpy(file, file, MAX_PATH_LENGTH);
            } else if (strncmp(current_dir, "/", 1) == 0 &&
                       strlen(current_dir) == 1) {
                file = concat(concat(current_dir, ""), file);
            } else {
                file = concat(concat(current_dir, "/"), file);
            }

            toupper(file);
            write("Reading: ");
            write(file);
            write("\n");

            str content = read_file(file);
            if (content == NULL) {
                write("ERROR: File not found\n");
            } else {
                write(content);
            }
        } else if (strncmp(input, "write", 5) == 0) {
            write_command(input);
        } else if (strncmp(input, "help", 4) == 0) {
            write("Available commands:\n");
            write("ls - List directory contents\n");
            write("cd - Change directory\n");
            write("clear - Clear the screen\n");
            write("about - Display system information\n");
            write("exists? -d - Check if a directory exists\n");
            write("exists? - Check if a file exists\n");
            write("read - Read file contents\n");
            write("help - Display this help message\n");
        } else if (strncmp(input, "disk", 4) == 0) {
            str rest = input + 5;
            disk_utility(rest);
        } else {
            if (strlen(input) > 0) {
                write("Unknown command\n");
            }
        }
    }
}

void write_command(str command) {
    str rest = command + 6;
    bool to_file = strcontains(rest, "to");
    if (!to_file) {
        size len = strlen(rest);
        if (rest[len - 1] == '"' && rest[0] == '"') {
            rest[len - 1] = 0;
            rest++;
        }
        write(rest);
        write("\n");
    } else {
        size len = strfind(rest, 't') - 1;
        str file = rest + len + 4;
        str contents = rest;
        if (contents[len - 1] == '"' && contents[0] == '"') {
            contents[len - 1] = 0;
            contents++;
        }

        if (file[0] == '.' && file[1] == '/') {
            file = concat(current_dir, file + 2);
        } else if (strncmp(file, "/", 1) == 0) {
            file = "/";
        } else if (file[0] == '/') {
            strncpy(file, file, MAX_PATH_LENGTH);
        } else if (strncmp(current_dir, "/", 1) == 0) {
            file = concat(concat(current_dir, ""), file);
        } else {
            file = concat(concat(current_dir, "/"), file);
        }

        toupper(file);

        if (file_exists(file)) {
            write_to_file(file, contents);
        } else {
            create_file(file);
        }
    }
}
